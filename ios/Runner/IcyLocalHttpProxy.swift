import Foundation
import Network

/// Local HTTP proxy for ICY (Shoutcast/Icecast) streams.
///
/// Architecture: listen on 127.0.0.1:<auto-assigned-port> and serve a plain
/// HTTP/1.1 response to AVPlayer. Under the hood we open ONE upstream HTTPS
/// connection to the real stream host, strip out ICY metadata blocks, and
/// forward the clean audio bytes to AVPlayer. Metadata fires through a
/// callback to the plugin.
///
/// Why not AVAssetResourceLoader? We tried — it works on iOS but fails on
/// macOS with CoreMediaErrorDomain -1002 (== NSURLErrorUnsupportedURL).
/// CoreMedia has internal paths that bypass the resource-loader delegate
/// and try to resolve the custom scheme through CFNetwork, which doesn't
/// know about it. The local-proxy pattern sidesteps that by serving a real
/// `http://127.0.0.1/…` URL — every AVFoundation subsystem can follow it.
///
/// Single upstream connection preserves the bandwidth-courtesy property
/// (important for both cellular on the client AND the stream host).
final class IcyLocalHttpProxy: NSObject {
    /// 127.0.0.1 — localhost loopback. Never exposed externally.
    static let listenHost = "127.0.0.1"

    let upstreamURL: URL
    private let onMetadata: (String) -> Void
    private let onHeaders:
        (_ name: String?, _ genre: String?, _ bitrate: Int?, _ streamUrl: String?)
            -> Void
    private let onError: (Error) -> Void

    /// Port bound after `start()` returns. Readable via `playbackURL`.
    private(set) var port: UInt16 = 0

    /// URL AVPlayer should connect to. Only valid after `start()`.
    var playbackURL: URL? {
        guard port > 0 else { return nil }
        // Preserve the original path so radio-browser fingerprinting etc.
        // still sees a plausible URL in logs. Host and port are forced to
        // our listener's loopback endpoint.
        var components =
            URLComponents(url: upstreamURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        components.scheme = "http"
        components.host = Self.listenHost
        components.port = Int(port)
        components.user = nil
        components.password = nil
        return components.url
    }

    private var listener: NWListener?
    private var clientConnection: NWConnection?
    private var upstreamSession: URLSession?
    private var upstreamTask: URLSessionDataTask?

    /// True once `startUpstreamIfNeeded` has kicked off a dataTask. Stays
    /// true even after the task completes — prevents a second client (the
    /// probe-vs-playback pattern AVPlayer uses) from starting a duplicate
    /// upstream, which would double-feed bytes into our ICY parser and
    /// produce repeated/stuttering audio.
    private var upstreamStarted = false
    /// True once we've parsed upstream response headers. Until then, newly-
    /// connected clients wait for the initial response before their HTTP
    /// headers can be sent.
    private var upstreamHeadersReady = false

    private var contentType: String = "audio/mpeg"
    private var clientResponseSent = false
    private var finished = false

    /// ICY byte stripper state.
    private var metaint: Int = 0
    private var audioBytesSinceMetadata: Int = 0
    private var metadataBuffer = Data()
    private var remainingMetadataLength: Int = 0
    private var awaitingLengthByte = false

    /// Single serial queue for all state mutations.
    private let queue = DispatchQueue(
        label: "com.justradio.icy-proxy", qos: .userInitiated)

    /// Flip to true when debugging stream connectivity. Adds request-dump
    /// and per-chunk delivery logs; keep off in release so Console.app
    /// stays clean. Lifecycle-level errors still print unconditionally.
    private static let verboseLogging = false
    private static func vlog(_ message: @autoclosure () -> String) {
        if verboseLogging { print("[icy-proxy] \(message())") }
    }

    init(
        upstreamURL: URL,
        onMetadata: @escaping (String) -> Void,
        onHeaders: @escaping (String?, String?, Int?, String?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.upstreamURL = upstreamURL
        self.onMetadata = onMetadata
        self.onHeaders = onHeaders
        self.onError = onError
    }

    /// Bind an NWListener on 127.0.0.1 with an OS-assigned port and block
    /// the caller until the listener reports `.ready`. Returns the bound
    /// port. Typical wait is a few ms; the 5-second timeout is a safety
    /// net — if it trips, something's wrong with the OS or sandbox.
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        // Listen ONLY on the loopback interface — no external exposure.
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        let semaphore = DispatchSemaphore(value: 0)
        var listenerError: Error?

        listener.newConnectionHandler = { [weak self] conn in
            self?.acceptClient(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                semaphore.signal()
            case .failed(let err):
                listenerError = err
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        if semaphore.wait(timeout: .now() + 5.0) == .timedOut {
            listener.cancel()
            throw NSError(
                domain: "IcyLocalHttpProxy",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "NWListener did not become ready"
                ]
            )
        }
        if let err = listenerError { throw err }
        guard let rawPort = listener.port?.rawValue else {
            throw NSError(
                domain: "IcyLocalHttpProxy",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "NWListener has no port"]
            )
        }
        self.port = rawPort
        Self.vlog("listening on \(Self.listenHost):\(rawPort)")
        return rawPort
    }

    /// Tear down both directions. Safe to call from any thread and multiple
    /// times.
    func shutdown() {
        queue.async { [weak self] in
            guard let self = self, !self.finished else { return }
            self.finished = true
            Self.vlog("shutdown")
            self.upstreamTask?.cancel()
            self.upstreamSession?.invalidateAndCancel()
            self.upstreamTask = nil
            self.upstreamSession = nil
            self.clientConnection?.cancel()
            self.clientConnection = nil
            self.listener?.cancel()
            self.listener = nil
        }
    }

    // ------------------------------------------------------------------
    // Client side (AVPlayer → us)
    // ------------------------------------------------------------------

    private func acceptClient(_ conn: NWConnection) {
        if finished {
            conn.cancel()
            return
        }
        // AVPlayer typically opens two sequential connections: a short
        // probe (HEAD or Range request) then the real playback connection.
        // Replace the old client without tearing the listener down.
        if let existing = clientConnection {
            Self.vlog("replacing previous client connection")
            existing.cancel()
        }
        Self.vlog("client connected")
        clientConnection = conn
        clientResponseSent = false
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let err):
                Self.vlog("client state failed: \(err) — keeping listener alive for reconnect")
                // Only clear the client slot. Listener stays up so AVPlayer
                // can reconnect for the real playback request.
                if self.clientConnection === conn {
                    self.clientConnection = nil
                    self.clientResponseSent = false
                }
            case .cancelled:
                if self.clientConnection === conn {
                    self.clientConnection = nil
                    self.clientResponseSent = false
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
        readClientRequest(conn)
    }

    /// Read the client's HTTP request headers and kick off the upstream
    /// fetch. We don't parse the headers — AVPlayer asks for exactly what
    /// we'd send anyway (a GET of the whole resource) — we just need to
    /// drain the request bytes until `\r\n\r\n` so the socket is ready to
    /// receive our response.
    private func readClientRequest(_ conn: NWConnection) {
        var accumulated = Data()
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if let error = error {
                    Self.vlog("client read error: \(error)")
                    self.shutdown()
                    return
                }
                if let data = data, !data.isEmpty {
                    accumulated.append(data)
                    if accumulated.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
                        != nil
                    {
                        if Self.verboseLogging {
                            // Request-line preview for HEAD/GET/Range debug.
                            let preview = String(
                                data: accumulated.prefix(400),
                                encoding: .utf8
                            )?.replacingOccurrences(of: "\r\n", with: " | ")
                                ?? "?"
                            print("[icy-proxy] client request (\(accumulated.count)B): \(preview)")
                        }
                        self.startUpstreamIfNeeded()
                        // If upstream has already responded by the time this
                        // client arrived (second-client probe/playback case),
                        // we have headers cached and can send our response
                        // immediately. Otherwise send waits for upstream.
                        if self.upstreamHeadersReady {
                            self.sendClientResponseHeaders()
                        }
                        return
                    }
                }
                if isComplete {
                    Self.vlog("client closed before request complete")
                    self.shutdown()
                    return
                }
                readMore()
            }
        }
        readMore()
    }

    private func sendClientResponseHeaders() {
        guard !clientResponseSent, let conn = clientConnection else { return }
        clientResponseSent = true
        // HTTP/1.0 + Connection: close signals "read until the socket closes"
        // — no Content-Length needed for a live stream.
        let header =
            "HTTP/1.0 200 OK\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Connection: close\r\n"
            + "Cache-Control: no-cache\r\n"
            + "\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        conn.send(content: headerData, completion: .contentProcessed { _ in })
    }

    private func sendClientAudio(_ data: Data) {
        guard let conn = clientConnection, !data.isEmpty else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // ------------------------------------------------------------------
    // Upstream side (us → real host) — ICY aware
    // ------------------------------------------------------------------

    private func startUpstreamIfNeeded() {
        guard !upstreamStarted else { return }
        upstreamStarted = true
        var request = URLRequest(url: upstreamURL)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = .infinity
        let session = URLSession(
            configuration: config, delegate: self, delegateQueue: nil)
        upstreamSession = session
        let task = session.dataTask(with: request)
        upstreamTask = task
        Self.vlog("starting upstream: \(upstreamURL.absoluteString)")
        task.resume()
    }

    private func consumeUpstream(_ data: Data) {
        guard !data.isEmpty else { return }
        if metaint <= 0 {
            // No ICY metadata at all — forward everything as audio.
            sendClientAudio(data)
            return
        }

        var offset = 0
        while offset < data.count {
            if awaitingLengthByte {
                let lengthByte = data[
                    data.index(data.startIndex, offsetBy: offset)]
                offset += 1
                let length = Int(lengthByte) * 16
                awaitingLengthByte = false
                if length > 0 {
                    remainingMetadataLength = length
                    metadataBuffer = Data()
                } else {
                    audioBytesSinceMetadata = 0
                }
                continue
            }

            if remainingMetadataLength > 0 {
                let toRead = min(remainingMetadataLength, data.count - offset)
                let start = data.index(data.startIndex, offsetBy: offset)
                let slice = data.subdata(
                    in: start..<data.index(start, offsetBy: toRead))
                metadataBuffer.append(slice)
                remainingMetadataLength -= toRead
                offset += toRead
                if remainingMetadataLength == 0 {
                    emitMetadataBuffer()
                    audioBytesSinceMetadata = 0
                }
                continue
            }

            let remainingInAudioRun = metaint - audioBytesSinceMetadata
            let toRead = min(remainingInAudioRun, data.count - offset)
            let start = data.index(data.startIndex, offsetBy: offset)
            let slice = data.subdata(
                in: start..<data.index(start, offsetBy: toRead))
            sendClientAudio(slice)
            audioBytesSinceMetadata += toRead
            offset += toRead
            if audioBytesSinceMetadata >= metaint {
                awaitingLengthByte = true
            }
        }
    }

    private func emitMetadataBuffer() {
        let trimmed = metadataBuffer.prefix { $0 != 0x00 }
        defer { metadataBuffer = Data() }
        guard !trimmed.isEmpty,
            let raw = String(data: Data(trimmed), encoding: .utf8),
            let title = Self.parseStreamTitle(from: raw),
            !title.isEmpty
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMetadata(title)
        }
    }

    static func parseStreamTitle(from raw: String) -> String? {
        guard let range = raw.range(of: "StreamTitle='") else { return nil }
        let start = range.upperBound
        guard let end = raw.range(of: "';", range: start..<raw.endIndex)
        else { return nil }
        let value = String(raw[start..<end.lowerBound])
        return value.isEmpty ? nil : value
    }
}

// ------------------------------------------------------------------
// URLSessionDataDelegate
// ------------------------------------------------------------------

extension IcyLocalHttpProxy: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self, !self.finished else {
                completionHandler(.cancel)
                return
            }
            if let http = response as? HTTPURLResponse {
                Self.vlog("upstream status=\(http.statusCode) headers=\(http.allHeaderFields.count)")
                let headers = http.allHeaderFields
                func val(_ key: String) -> String? {
                    for (k, v) in headers {
                        if let ks = k as? String,
                            ks.lowercased() == key.lowercased()
                        {
                            return v as? String
                        }
                    }
                    return nil
                }
                if let m = val("icy-metaint").flatMap({ Int($0) }) {
                    self.metaint = m
                }
                if let ct = val("content-type"), !ct.isEmpty {
                    self.contentType = ct
                }
                self.upstreamHeadersReady = true
                let name = val("icy-name")
                let genre = val("icy-genre")
                let bitrate = val("icy-br").flatMap { Int($0) }
                let streamUrl = val("icy-url")
                DispatchQueue.main.async {
                    self.onHeaders(name, genre, bitrate, streamUrl)
                }
                // Tell whichever client is currently connected — they've
                // been waiting for us to have headers.
                self.sendClientResponseHeaders()
            }
            completionHandler(.allow)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        queue.async { [weak self] in
            self?.consumeUpstream(data)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let error = error, (error as NSError).code != NSURLErrorCancelled
            {
                // Keep this one unconditional — upstream errors are always
                // worth seeing when a station fails to play.
                print("[icy-proxy] upstream error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError(error)
                }
            } else {
                Self.vlog("upstream ended")
            }
            // Close the client — AVPlayer sees EOF and stops. Keeps the
            // player state consistent with upstream.
            self.clientConnection?.cancel()
        }
    }
}
