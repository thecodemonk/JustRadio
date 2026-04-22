import AVFoundation
import Flutter
import MediaPlayer

/// Native iOS audio engine for JustRadio. Wraps AVPlayer and surfaces:
///   - playback state changes (via KVO on timeControlStatus / status)
///   - timed metadata (ICY StreamTitle on Shoutcast/Icecast, ID3 TIT2/TPE1
///     on HLS streams) via AVPlayerItemMetadataOutput — uniform for both
///     protocols, which just_audio's icyMetadataStream does not provide.
public class AudioPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    AVPlayerItemMetadataOutputPushDelegate
{
    // Flip to true to emit verbose metadata-pipeline debug events over the
    // event channel (ID3-frame dumps, AVPlayer access log, KVO ticks, etc.).
    // Off by default — the chatter is only useful when debugging a specific
    // stream that isn't behaving as expected.
    private static let verboseLogging = false

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var eventSink: FlutterEventSink?
    private var kvoObservers: [NSKeyValueObservation] = []
    private var icyReader: IcyMetadataReader?
    private var lastStreamTitle: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AudioPlayerPlugin()
        let methodChannel = FlutterMethodChannel(
            name: "justradio/audio", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: "justradio/audio/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "ping":
            // Parity with Android; Dart uses this to confirm the channel is
            // registered before subscribing. iOS usually doesn't race but the
            // method is cheap to support.
            result(true)
        case "playStation":
            let url = args?["url"] as? String ?? ""
            playStation(urlString: url)
            result(nil)
        case "play":
            player?.play()
            result(nil)
        case "pause":
            player?.pause()
            result(nil)
        case "stop":
            stopPlayer()
            result(nil)
        case "setVolume":
            if let volume = args?["volume"] as? Double {
                player?.volume = Float(max(0.0, min(1.0, volume)))
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments _: Any?, eventSink: @escaping FlutterEventSink)
        -> FlutterError?
    {
        self.eventSink = eventSink
        return nil
    }

    public func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func playStation(urlString: String) {
        stopPlayer()

        guard let url = URL(string: urlString) else {
            sendEvent(["type": "state", "state": "error", "message": "Invalid URL"])
            return
        }

        // Playback category so audio continues when locked / ringer off / backgrounded.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioPlayerPlugin: failed to activate audio session: \(error)")
        }

        // AVPlayer does not send Icy-MetaData: 1 by default, so Shoutcast /
        // Icecast servers (e.g. SomaFM) omit StreamTitle markers from the
        // stream entirely — audio plays but no metadata arrives. We opt in
        // via AVURLAssetHTTPHeaderFieldsKey. Harmless for HLS.
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Icy-MetaData": "1"]
            ])
        let item = AVPlayerItem(asset: asset)

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: DispatchQueue.main)
        item.add(output)
        metadataOutput = output
        sendDebug("attached metadata output + timedMetadata KVO for \(urlString)")

        let statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            self?.handleStatus(item: item)
        }
        kvoObservers.append(statusObs)

        // Belt + suspenders: AVPlayerItemMetadataOutput is the modern API, but
        // in practice AVPlayer surfaces ICY StreamTitle via the older
        // AVPlayerItem.timedMetadata KVO property for Shoutcast/Icecast
        // streams. Observe both — whichever fires first wins.
        let timedObs = item.observe(
            \.timedMetadata, options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.handleTimedMetadata(items: item.timedMetadata ?? [])
        }
        kvoObservers.append(timedObs)

        let newPlayer = AVPlayer(playerItem: item)
        let timeObs = newPlayer.observe(\.timeControlStatus, options: [.new]) {
            [weak self] p, _ in
            self?.handleTimeControl(player: p)
        }
        kvoObservers.append(timeObs)

        player = newPlayer
        playerItem = item

        // Access-log notifications tell us the stream's actual bitrate, which
        // is especially useful for HLS where Radio Browser's station.bitrate
        // is typically 0. Fires shortly after playback starts.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAccessLogEntry(_:)),
            name: .AVPlayerItemNewAccessLogEntry,
            object: item
        )

        sendEvent(["type": "state", "state": "loading"])
        newPlayer.play()

        // Side-channel ICY reader — AVPlayer's built-in ICY parsing is
        // unreliable on iOS (confirmed silent on SomaFM HTTPS endpoints),
        // so we parse metadata ourselves from a parallel connection.
        // HLS streams don't use ICY — skip for those.
        if !urlString.contains(".m3u8") {
            startIcyReader(for: url)
        }
    }

    private func startIcyReader(for url: URL) {
        icyReader?.stop()
        lastStreamTitle = nil
        let reader = IcyMetadataReader(
            url: url,
            onMetadata: { [weak self] raw, title in
                self?.handleIcyMetadata(raw: raw, title: title)
            },
            onHeaders: { [weak self] name, genre, bitrate, streamUrl in
                self?.sendEvent([
                    "type": "metadata",
                    "identifier": "icy/headers",
                    "streamName": name as Any,
                    "genre": genre as Any,
                    "bitrate": bitrate as Any,
                    "streamUrl": streamUrl as Any,
                ])
            },
            onError: { [weak self] error in
                self?.sendDebug("icy reader error: \(error.localizedDescription)")
            }
        )
        icyReader = reader
        reader.start()
        sendDebug("started icy side-channel reader")
    }

    private func handleIcyMetadata(raw: String, title: String?) {
        guard let title = title, !title.isEmpty, title != lastStreamTitle else {
            return
        }
        lastStreamTitle = title
        sendEvent([
            "type": "metadata",
            "identifier": "icy/StreamTitle",
            "source": "icyReader",
            "stringValue": title,
            "title": title,
        ])
    }

    private func stopPlayer() {
        player?.pause()
        for obs in kvoObservers { obs.invalidate() }
        kvoObservers = []
        if let item = playerItem {
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemNewAccessLogEntry, object: item)
            if let output = metadataOutput {
                item.remove(output)
            }
        }
        metadataOutput = nil
        playerItem = nil
        player = nil
        icyReader?.stop()
        icyReader = nil
        lastStreamTitle = nil
        sendEvent(["type": "state", "state": "stopped"])
    }

    @objc private func onAccessLogEntry(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem else { return }

        let trackBps = item.tracks.lazy
            .filter { $0.isEnabled }
            .compactMap { $0.assetTrack }
            .first { $0.mediaType == .audio }?
            .estimatedDataRate ?? 0

        let lastEvent = item.accessLog()?.events.last
        let indicated = lastEvent?.indicatedBitrate ?? 0
        let indicatedAvg = lastEvent?.indicatedAverageBitrate ?? 0
        let observed = lastEvent?.observedBitrate ?? 0

        sendDebug(
            "access log: track=\(Int(trackBps / 1000)) indicated=\(Int(indicated / 1000)) indicatedAvg=\(Int(indicatedAvg / 1000)) observed=\(Int(observed / 1000))"
        )

        let logBps: Double = {
            if indicated > 0 { return indicated }
            if indicatedAvg > 0 { return indicatedAvg }
            return observed
        }()

        let bpsCandidate = trackBps > 0 ? Double(trackBps) : logBps
        let kbps = Int(bpsCandidate / 1000)
        // Floor filter: anything under 64 kbps is either AVPlayer's early-
        // buffering noise (observed ~39 kbps seen in practice for HLS FLAC)
        // or too low for music. If the true rate can't be measured, showing
        // nothing is better than showing garbage.
        guard kbps >= 64 else { return }
        sendEvent([
            "type": "metadata",
            "identifier": "stream/info",
            "bitrate": kbps,
        ])
    }

    private func handleStatus(item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            // Playing state is emitted from timeControlStatus; "ready" here
            // just signals the asset is loaded.
            break
        case .failed:
            sendEvent([
                "type": "state",
                "state": "error",
                "message": item.error?.localizedDescription ?? "Player item failed",
            ])
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleTimeControl(player: AVPlayer) {
        switch player.timeControlStatus {
        case .playing:
            sendEvent(["type": "state", "state": "playing"])
        case .paused:
            sendEvent(["type": "state", "state": "paused"])
        case .waitingToPlayAtSpecifiedRate:
            sendEvent(["type": "state", "state": "loading"])
        @unknown default:
            break
        }
    }

    public func metadataOutput(
        _: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from _: AVPlayerItemTrack?
    ) {
        sendDebug("metadataOutput fired, groups=\(groups.count)")
        for group in groups {
            for item in group.items {
                emitMetadataItem(item, source: "output")
            }
        }
    }

    private func handleTimedMetadata(items: [AVMetadataItem]) {
        sendDebug("timedMetadata KVO fired, items=\(items.count)")
        for item in items {
            emitMetadataItem(item, source: "timedMetadata")
        }
    }

    private func emitMetadataItem(_ item: AVMetadataItem, source: String) {
        let identifier = item.identifier?.rawValue
        let commonKey = item.commonKey?.rawValue
        let keySpace = item.keySpace?.rawValue
        let stringValue = item.stringValue

        // Map well-known ID3 / ICY identifiers to named fields so Dart can
        // build a complete NowPlaying without parsing identifier strings.
        //   TIT2 / StreamTitle / commonKeyTitle → title
        //   TPE1 → artist
        //   TALB → album
        var title: String?
        var artist: String?
        var album: String?
        var codec: String?
        var bitrate: Int?
        var txxxDescriptor: String?

        if let id = identifier {
            if id.contains("StreamTitle") || id.hasSuffix("TIT2")
                || id.hasSuffix("/title")
            {
                title = stringValue
            } else if id.hasSuffix("TPE1") {
                artist = stringValue
            } else if id.hasSuffix("TALB") {
                album = stringValue
            } else if id.hasSuffix("TFLT") {
                codec = stringValue
            } else if id.hasSuffix("TXXX") {
                // User-defined text frame: descriptor lives in extraAttributes
                // under the `info` key. SomaFM HLS uses TXXX frames for
                // bitrate/sampleRate/channels — we route the bitrate one
                // through as the authoritative source for HLS display.
                if let extra = item.extraAttributes {
                    for (k, v) in extra {
                        let keyStr = String(describing: k).lowercased()
                        if keyStr.contains("info"), let s = v as? String {
                            txxxDescriptor = s
                        }
                    }
                }
                if let v = stringValue, let n = Int(v) {
                    let desc = txxxDescriptor?.lowercased() ?? ""
                    // Known bitrate descriptors (including SomaFM's 3-letter
                    // codes: `adr` = audio data rate, `br` = bitrate).
                    let bitrateKeys = ["bitrate", "kbps", "adr", "audiodatarate", "br"]
                    // Known non-bitrate (sample rate / channels / misc) so we
                    // skip the range heuristic for them.
                    let nonBitrateKeys = [
                        "sample", "asr", "channel", "ach", "enc", "dev", "crd",
                        "date", "time", "year",
                    ]
                    let isBitrate = bitrateKeys.contains { desc.contains($0) }
                    let isKnownOther = nonBitrateKeys.contains { desc.contains($0) }
                    // If no descriptor or descriptor is unrecognized, fall
                    // back to value-range heuristic. 64–2000 kbps covers all
                    // realistic music bitrates and excludes sample rates
                    // (≥8000) and channel counts (1–8).
                    let isRangeBitrate =
                        !isKnownOther && n >= 64 && n <= 2000
                    if isBitrate || isRangeBitrate {
                        bitrate = n
                    }
                }
            }
        }
        if title == nil, commonKey == AVMetadataKey.commonKeyTitle.rawValue {
            title = stringValue
        }

        sendEvent([
            "type": "metadata",
            "source": source,
            "identifier": identifier as Any,
            "commonKey": commonKey as Any,
            "keySpace": keySpace as Any,
            "stringValue": stringValue as Any,
            "title": title as Any,
            "artist": artist as Any,
            "album": album as Any,
            "codec": codec as Any,
            "bitrate": bitrate as Any,
            "txxxDescriptor": txxxDescriptor as Any,
        ])
    }

    private func sendEvent(_ payload: [String: Any?]) {
        let cleaned = payload.mapValues { $0 ?? NSNull() }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(cleaned)
        }
    }

    private func sendDebug(_ message: @autoclosure () -> String) {
        guard Self.verboseLogging else { return }
        sendEvent(["type": "debug", "message": message()])
    }
}
