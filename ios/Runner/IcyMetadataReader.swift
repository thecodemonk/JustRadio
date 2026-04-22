import Foundation

/// Reads ICY (Shoutcast/Icecast) metadata from a stream by opening its own
/// HTTP connection with `Icy-MetaData: 1`, alongside the AVPlayer that's
/// actually rendering audio. AVPlayer's built-in ICY handling is unreliable
/// on recent iOS versions (confirmed silent on https://ice5.somafm.com/*),
/// so we parse the bytes ourselves.
///
/// Protocol:
///   - Server responds with `icy-metaint: N` — every N bytes of audio, a
///     metadata block is inlined.
///   - Each metadata block starts with a 1-byte length indicator (multiply
///     by 16 for the real length).
///   - Body of the block is null-padded ASCII, e.g.
///     `StreamTitle='Artist - Title';StreamUrl='http://...';`
///
/// HLS streams (`.m3u8`) don't use ICY — callers must gate on URL type.
final class IcyMetadataReader: NSObject {
    private let url: URL
    private let onMetadata: (_ rawBlock: String, _ streamTitle: String?) -> Void
    private let onHeaders: (_ name: String?, _ genre: String?, _ bitrate: Int?, _ url: String?) -> Void
    private let onError: (Error) -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var metaint: Int = 0
    private var audioBytesSinceMetadata: Int = 0
    private var metadataBuffer = Data()
    private var remainingMetadataLength: Int = 0
    private var awaitingLengthByte = false

    init(
        url: URL,
        onMetadata: @escaping (_ rawBlock: String, _ streamTitle: String?) -> Void,
        onHeaders: @escaping (_ name: String?, _ genre: String?, _ bitrate: Int?, _ url: String?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.url = url
        self.onMetadata = onMetadata
        self.onHeaders = onHeaders
        self.onError = onError
    }

    func start() {
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        let config = URLSessionConfiguration.default
        // Long streams — avoid the default 60s resource timeout killing us
        // mid-song, which would look like "metadata stopped" to the user.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        metaint = 0
        audioBytesSinceMetadata = 0
        metadataBuffer = Data()
        remainingMetadataLength = 0
        awaitingLengthByte = false
    }

    private func processChunk(_ data: Data) {
        // No ICY metadata in this stream — nothing to parse. Discard.
        guard metaint > 0 else { return }

        var offset = 0
        while offset < data.count {
            if awaitingLengthByte {
                let lengthByte = data[data.index(data.startIndex, offsetBy: offset)]
                offset += 1
                let length = Int(lengthByte) * 16
                awaitingLengthByte = false
                if length > 0 {
                    remainingMetadataLength = length
                    metadataBuffer = Data()
                } else {
                    // Empty metadata frame — go back to counting audio.
                    audioBytesSinceMetadata = 0
                }
                continue
            }

            if remainingMetadataLength > 0 {
                let toRead = min(remainingMetadataLength, data.count - offset)
                let slice = data.subdata(
                    in: data.index(data.startIndex, offsetBy: offset)
                        ..< data.index(data.startIndex, offsetBy: offset + toRead))
                metadataBuffer.append(slice)
                remainingMetadataLength -= toRead
                offset += toRead
                if remainingMetadataLength == 0 {
                    emitMetadataBuffer()
                    audioBytesSinceMetadata = 0
                }
                continue
            }

            if audioBytesSinceMetadata < metaint {
                let toSkip = min(metaint - audioBytesSinceMetadata, data.count - offset)
                audioBytesSinceMetadata += toSkip
                offset += toSkip
                continue
            }

            // Reached a metadata boundary — next byte is the length indicator.
            awaitingLengthByte = true
        }
    }

    private func emitMetadataBuffer() {
        // Metadata is null-padded ASCII. Trim trailing zeros.
        let trimmed = metadataBuffer.prefix { $0 != 0x00 }
        guard !trimmed.isEmpty,
            let raw = String(data: Data(trimmed), encoding: .utf8)
        else {
            metadataBuffer = Data()
            return
        }
        let streamTitle = Self.parseStreamTitle(from: raw)
        onMetadata(raw, streamTitle)
        metadataBuffer = Data()
    }

    static func parseStreamTitle(from raw: String) -> String? {
        // Format examples:
        //   StreamTitle='Artist - Title';StreamUrl='';
        //   StreamTitle='Track';
        guard let range = raw.range(of: "StreamTitle='") else { return nil }
        let start = range.upperBound
        guard let end = raw.range(of: "';", range: start..<raw.endIndex) else { return nil }
        let value = String(raw[start..<end.lowerBound])
        return value.isEmpty ? nil : value
    }
}

extension IcyMetadataReader: URLSessionDataDelegate {
    func urlSession(
        _: URLSession, dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            // Header names are case-insensitive per HTTP spec; allHeaderFields
            // is one place that actually preserves case. Try both conventions.
            let headers = http.allHeaderFields
            func headerValue(_ key: String) -> String? {
                for (k, v) in headers {
                    if let ks = k as? String, ks.lowercased() == key.lowercased() {
                        return v as? String
                    }
                }
                return nil
            }

            if let metaintStr = headerValue("icy-metaint"),
                let m = Int(metaintStr)
            {
                metaint = m
            }

            let name = headerValue("icy-name")
            let genre = headerValue("icy-genre")
            let bitrate = headerValue("icy-br").flatMap { Int($0) }
            let streamUrl = headerValue("icy-url")
            onHeaders(name, genre, bitrate, streamUrl)
        }
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data
    ) {
        processChunk(data)
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            onError(error)
        }
    }
}
