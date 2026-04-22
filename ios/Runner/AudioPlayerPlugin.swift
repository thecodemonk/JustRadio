import AVFoundation
import MediaPlayer

// Flutter's iOS + macOS SDKs ship under different module names. Same
// FlutterPlugin protocol, same FlutterMethodChannel/FlutterEventChannel
// types — just a different import header.
#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif

// UIImage on iOS, NSImage on macOS — artwork loading uses the
// platform-appropriate type when building MPMediaItemArtwork.
#if os(iOS)
typealias JRPlatformImage = UIImage
#elseif os(macOS)
typealias JRPlatformImage = NSImage
#endif

/// Native AVFoundation audio engine for JustRadio. Shared between iOS and
/// macOS — both platforms run the same AVPlayer + AVAssetResourceLoader
/// plumbing and expose metadata through AVPlayerItemMetadataOutput plus the
/// ICY resource-loader proxy. Android uses a separate MediaSession-based
/// plugin; Windows/Linux desktops stay on media_kit.
///
/// Surfaces:
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

    /// Singleton reference for CarPlay. The CarPlay scene delegate runs in a
    /// separate UIScene and needs to reach the live AVPlayer — exposed via
    /// this property once the plugin registers with the Flutter engine.
    public static weak var shared: AudioPlayerPlugin?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var eventSink: FlutterEventSink?
    private var kvoObservers: [NSKeyValueObservation] = []
    /// Local HTTP proxy that serves AVPlayer from 127.0.0.1, opens one
    /// upstream connection to the real stream host, and strips ICY
    /// metadata blocks out of the byte stream on the way. Replaces the
    /// earlier AVAssetResourceLoader custom-scheme approach which hit
    /// CoreMediaErrorDomain -1002 on macOS.
    private var icyLocalProxy: IcyLocalHttpProxy?
    private var lastStreamTitle: String?
    private var currentStationName: String?
    private var currentFaviconUrl: String?
    /// Per-track album art (phase 5). Takes priority over the station
    /// favicon while the current track has a resolved image.
    private var currentAlbumArtUrl: String?
    private var remoteCommandsConfigured = false

    /// Remembered volume (the logarithmic value Dart already applied). Each
    /// playStation spins up a fresh AVPlayer; without this we'd reset to
    /// 1.0 on every station change — noticeable jump on macOS especially.
    private var lastVolume: Float = 1.0

    /// Generation counter for deferred ICY metadata emission. Incremented
    /// on every stopPlayer / playStation so metadata scheduled for a prior
    /// station (still waiting out AVPlayer's buffer delay) gets dropped
    /// instead of bleeding into the new station's UI.
    private var icyMetadataGeneration: UInt64 = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AudioPlayerPlugin()
        shared = instance
        // registrar.messenger is a method on iOS, a property on macOS. Same
        // FlutterBinaryMessenger type underneath.
        #if os(iOS)
        let messenger = registrar.messenger()
        #elseif os(macOS)
        let messenger = registrar.messenger
        #endif
        let methodChannel = FlutterMethodChannel(
            name: "justradio/audio", binaryMessenger: messenger)
        let eventChannel = FlutterEventChannel(
            name: "justradio/audio/events", binaryMessenger: messenger)
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
            let name = args?["name"] as? String ?? ""
            let favicon = args?["favicon"] as? String ?? ""
            currentStationName = name.isEmpty ? nil : name
            currentFaviconUrl = favicon.isEmpty ? nil : favicon
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
                let v = Float(max(0.0, min(1.0, volume)))
                lastVolume = v
                player?.volume = v
            }
            result(nil)
        case "syncFavorites":
            writeDefaultsJson(
                key: "justradio.favorites",
                value: args?["stations"] as? [[String: Any]] ?? []
            )
            result(nil)
        case "syncRecent":
            writeDefaultsJson(
                key: "justradio.recent",
                value: args?["stations"] as? [[String: Any]] ?? []
            )
            result(nil)
        case "syncGenres":
            writeDefaultsJson(
                key: "justradio.genres",
                value: args?["genres"] as? [[String: Any]] ?? []
            )
            result(nil)
        case "syncGenreStations":
            if let tag = args?["tag"] as? String, !tag.isEmpty {
                writeDefaultsJson(
                    key: "justradio.genre_stations.\(tag)",
                    value: args?["stations"] as? [[String: Any]] ?? []
                )
            }
            result(nil)
        case "setAlbumArt":
            let url = args?["url"] as? String
            // Swap the lock-screen / CarPlay artwork from the station logo to
            // the per-track album art while a resolved image is available.
            currentAlbumArtUrl = (url?.isEmpty ?? true) ? nil : url
            updateNowPlayingInfo()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func writeDefaultsJson(key: String, value: [[String: Any]]) {
        // Mirror the same JSON shape Android's PlaybackService reads from
        // SharedPreferences — CarPlay's CarPlayLibrary reads this store to
        // populate browse templates when the scene connects.
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Entry point used by the CarPlay scene delegate. Mirrors playStation
    /// from the method channel but bypasses Flutter.
    public func playStationFromCarPlay(url: String, name: String, favicon: String?) {
        currentStationName = name.isEmpty ? nil : name
        currentFaviconUrl = (favicon?.isEmpty ?? true) ? nil : favicon
        playStation(urlString: url)
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

        // Playback category so audio continues when locked / ringer off /
        // backgrounded. AVAudioSession is iOS-only — on macOS there is no
        // session to activate; audio plays regardless of app focus.
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioPlayerPlugin: failed to activate audio session: \(error)")
        }
        #endif

        // Lock-screen / control-center / CarPlay now-playing info + transport
        // commands. Cheap to configure on every play; the command registration
        // itself is idempotent.
        configureRemoteCommands()
        updateNowPlayingInfo()

        // HLS goes straight to AVURLAsset — AVPlayer handles segment-embedded
        // ID3 natively on both platforms. ICY (Shoutcast/Icecast) streams
        // run through the resource-loader proxy on both platforms so we
        // parse StreamTitle ourselves from the single audio connection
        // AVPlayer reads from — zero bandwidth doubling on either the
        // client *or the streaming host*.
        let isHls = urlString.contains(".m3u8")
        let asset: AVURLAsset
        if isHls {
            asset = AVURLAsset(url: url)
        } else {
            asset = makeIcyProxyAsset(for: url)
        }
        let item = AVPlayerItem(asset: asset)

        // HLS timed metadata lands on AVPlayerItemMetadataOutput; ICY is
        // handled upstream by IcyLocalHttpProxy so AVPlayer never sees
        // metadata blocks in the byte stream. We dropped the legacy
        // `timedMetadata` KVO observer that used to be here — it was
        // deprecated on macOS 10.15+ and is now dead code given this split.
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: DispatchQueue.main)
        item.add(output)
        metadataOutput = output

        let statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            self?.handleStatus(item: item)
        }
        kvoObservers.append(statusObs)

        let newPlayer = AVPlayer(playerItem: item)
        // Re-apply the last user-set volume — a fresh AVPlayer defaults to
        // 1.0, which caused a loud jump between stations on macOS where
        // there's no system-level attenuation to save us.
        newPlayer.volume = lastVolume
        let timeObs = newPlayer.observe(\.timeControlStatus, options: [.new]) {
            [weak self] p, _ in
            self?.handleTimeControl(player: p)
        }
        kvoObservers.append(timeObs)

        player = newPlayer
        playerItem = item

        // Extract the audio codec + sample rate from the track's format
        // description once tracks are loaded. HLS streams usually don't
        // include a TFLT ID3 frame, so this is the reliable codec source.
        extractAudioTrackInfo(from: item)

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
    }

    /// Build an AVURLAsset pointing at our local HTTP proxy. The proxy
    /// opens one upstream HTTPS connection to `originalUrl`, strips ICY
    /// metadata blocks, and serves clean audio on 127.0.0.1:<port>.
    /// AVPlayer sees a regular http:// URL — no custom scheme, no
    /// AVAssetResourceLoader, none of the internal-fetch failures we hit
    /// with that approach on macOS.
    private func makeIcyProxyAsset(for originalUrl: URL) -> AVURLAsset {
        let proxy = IcyLocalHttpProxy(
            upstreamURL: originalUrl,
            onMetadata: { [weak self] title in
                self?.handleIcyTitle(title)
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
                // Surface to Dart so the UI shows something meaningful
                // instead of silently dropping back to paused/stopped.
                // The proxy already printed the upstream error itself.
                self?.sendEvent([
                    "type": "state",
                    "state": "error",
                    "message": error.localizedDescription,
                ])
            }
        )
        do {
            _ = try proxy.start()
        } catch {
            // Last-resort fallback: play the stream directly and lose
            // ICY metadata. Not ideal but keeps audio working if the
            // local listener can't bind (rare — usually sandbox or port
            // exhaustion).
            print("[icy-proxy] start failed: \(error.localizedDescription) — falling back to direct playback")
            return AVURLAsset(url: originalUrl)
        }
        icyLocalProxy = proxy
        let playbackUrl = proxy.playbackURL ?? originalUrl
        return AVURLAsset(url: playbackUrl)
    }

    /// Read the audio format (codec + sample rate) from the player item's
    /// asset track once it's loaded, and emit codec as a metadata event.
    /// Radio Browser's `codec` field is the *container* (e.g. "MP4" for
    /// fMP4-HLS), which is useless for display — the real codec lives in
    /// the CMFormatDescription on the track.
    private func extractAudioTrackInfo(from item: AVPlayerItem) {
        // AVPlayerItem.tracks is deprecated-but-still-functional and is the
        // simplest cross-version API. The list is empty until playback is
        // about to start, so poll on a short delay; the first access-log
        // event will also retry via handleAccessLog.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.readAudioTrackInfo()
        }
    }

    private func readAudioTrackInfo() {
        guard let item = playerItem else { return }
        // Find the first enabled audio track.
        guard let assetTrack = item.tracks.lazy
            .filter({ $0.isEnabled })
            .compactMap({ $0.assetTrack })
            .first(where: { $0.mediaType == .audio })
        else {
            sendDebug("readAudioTrackInfo: no audio track yet")
            return
        }

        var emittedCodec: String?
        // Each track carries one or more CMFormatDescriptions; use the
        // first. Subtype is a FourCharCode like 'mp4a' (AAC), 'fLaC', 'mp3 '.
        if let desc = (assetTrack.formatDescriptions as? [CMFormatDescription])?.first {
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            emittedCodec = fourCCToCodecName(subType)
        }

        // estimatedDataRate is bits/sec for the track. For HLS variants
        // AVPlayer reports something close to the playlist BANDWIDTH; for
        // container formats it's the demuxer's estimate. Fall back to the
        // access log if this returns 0 (still buffering).
        let bps = assetTrack.estimatedDataRate
        var emittedBitrate: Int?
        if bps > 0 {
            emittedBitrate = Int(bps / 1000)
        }

        if emittedCodec == nil && emittedBitrate == nil { return }
        var payload: [String: Any?] = [
            "type": "metadata",
            "identifier": "stream/info",
        ]
        if let c = emittedCodec { payload["codec"] = c }
        if let b = emittedBitrate, b > 0 { payload["bitrate"] = b }
        sendEvent(payload)
    }

    /// Map a Core Media audio fourcc to a display name. Unknown codecs pass
    /// through as the raw fourcc so we never lie — if a stream's codec
    /// isn't in the table, at least the user sees the real four chars.
    private func fourCCToCodecName(_ code: FourCharCode) -> String {
        let fourcc = String(format: "%c%c%c%c",
            (code >> 24) & 0xff,
            (code >> 16) & 0xff,
            (code >> 8) & 0xff,
            code & 0xff
        )
        switch fourcc {
        case "mp4a": return "AAC"
        case "fLaC": return "FLAC"
        case "mp3 ", ".mp3": return "MP3"
        case "Opus", "opus": return "Opus"
        case "alac": return "ALAC"
        default: return fourcc.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    private func handleIcyTitle(_ title: String) {
        guard !title.isEmpty, title != lastStreamTitle else { return }
        lastStreamTitle = title
        // The proxy emits metadata at the UPSTREAM position. AVPlayer is
        // playing from its own buffer several seconds behind the wire. If
        // we publish immediately, the UI changes before the user actually
        // hears the new song. Defer by the buffered-ahead duration so the
        // title switch lands at the audio transition.
        let delay = calculateBufferedAhead()
        let token = icyMetadataGeneration
        let apply = { [weak self] in
            guard let self = self, self.icyMetadataGeneration == token else {
                // Station changed between arrival and emit — drop.
                return
            }
            self.applyIcyTitle(title)
        }
        if delay < 0.25 || delay > 60 {
            // No meaningful buffer yet, or a bogus value (CMTime weirdness
            // during early playback). Emit now.
            apply()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: apply)
        }
    }

    /// Commits a deferred ICY title to lock-screen metadata + Dart state.
    /// Only called when we're confident audio has caught up to the moment
    /// the upstream inserted this metadata marker.
    private func applyIcyTitle(_ title: String) {
        // Split "Artist - Title" (the common ICY convention) so lock-screen
        // metadata shows proper artist/track labels instead of the raw joined
        // string. The Dart side separately handles the split for its own
        // NowPlaying state.
        if let range = title.range(of: " - ") {
            lastTrackArtist = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            lastTrackTitle = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            lastTrackArtist = nil
            lastTrackTitle = title
        }
        updateNowPlayingInfo()
        sendEvent([
            "type": "metadata",
            "identifier": "icy/StreamTitle",
            "source": "icyLoader",
            "stringValue": title,
            "title": title,
        ])
    }

    /// Seconds of audio AVPlayer has buffered past its current playback
    /// position. Used to defer metadata emission so UI changes align with
    /// what the user actually hears. Returns 0 when we can't compute
    /// (no player item, no loaded ranges, NaN CMTime).
    private func calculateBufferedAhead() -> TimeInterval {
        guard let item = playerItem,
              let rangeValue = item.loadedTimeRanges.first
        else { return 0 }
        let range = rangeValue.timeRangeValue
        let endOfBuffer = CMTimeAdd(range.start, range.duration)
        let diff = CMTimeSubtract(endOfBuffer, item.currentTime())
        let seconds = CMTimeGetSeconds(diff)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func stopPlayer() {
        // Invalidate any deferred ICY metadata so it doesn't fire against a
        // fresh station's UI. Wraps around cleanly — overflow semantics are
        // fine, we only care about inequality.
        icyMetadataGeneration &+= 1
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
        icyLocalProxy?.shutdown()
        icyLocalProxy = nil
        lastStreamTitle = nil
        lastTrackTitle = nil
        lastTrackArtist = nil
        currentAlbumArtUrl = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        sendEvent(["type": "state", "state": "stopped"])
    }

    @objc private func onAccessLogEntry(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem else { return }

        // Retry the track-info extraction in case the initial 500ms poll
        // ran before AVPlayer populated the tracks array. By the time an
        // access log event fires, tracks are always ready.
        readAudioTrackInfo()

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
        // Floor filter: anything under 32 kbps is either AVPlayer's early-
        // buffering noise (observed ~39 kbps in practice for HLS FLAC
        // during early load) or too low for any music stream. Keep 32k so
        // 32k AAC-LC speech-radio streams still display correctly.
        guard kbps >= 32 else { return }
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
            // Dump everything we can about the failure so we can actually
            // diagnose resource-loader issues. `error` is a localized string
            // like "unsupported URL"; `errorLog` carries the chain of
            // underlying causes; `userInfo["NSUnderlyingError"]` often has
            // the real reason.
            let err = item.error as NSError?
            print("[icy] item FAILED: desc=\(err?.localizedDescription ?? "?") domain=\(err?.domain ?? "?") code=\(err?.code ?? 0)")
            if let under = err?.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("[icy]   underlying: desc=\(under.localizedDescription) domain=\(under.domain) code=\(under.code)")
            }
            if let log = item.errorLog() {
                for ev in log.events {
                    print("[icy]   errorLogEvent: status=\(ev.errorStatusCode) domain=\(ev.errorDomain) comment=\(ev.errorComment ?? "nil") uri=\(ev.uri ?? "nil")")
                }
            }
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
            updateNowPlayingPlaybackRate(1.0)
        case .paused:
            sendEvent(["type": "state", "state": "paused"])
            updateNowPlayingPlaybackRate(0.0)
        case .waitingToPlayAtSpecifiedRate:
            sendEvent(["type": "state", "state": "loading"])
        @unknown default:
            break
        }
    }

    // ------------------------------------------------------------------
    // MPNowPlayingInfoCenter + MPRemoteCommandCenter
    //
    // Populates the lock screen, Control Center, and CarPlay now-playing
    // surface. The artwork is loaded off the station's favicon URL; album-
    // art lookups (Phase 5) will replace it with actual track art once we
    // have (artist, title).
    // ------------------------------------------------------------------

    private func configureRemoteCommands() {
        if remoteCommandsConfigured { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let p = self?.player else { return .commandFailed }
            if p.timeControlStatus == .playing { p.pause() } else { p.play() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.stopPlayer()
            return .success
        }
        // Live radio — no seek, next, or previous.
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo(
        title: String? = nil,
        artist: String? = nil
    ) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title ?? lastTrackTitle ?? currentStationName ?? "JustRadio"
        info[MPMediaItemPropertyArtist] = artist ?? lastTrackArtist ?? currentStationName ?? ""
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded()
    }

    private func updateNowPlayingPlaybackRate(_ rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkIfNeeded() {
        // Prefer per-track album art when we have it, otherwise fall back to
        // the station favicon.
        let urlString = currentAlbumArtUrl ?? currentFaviconUrl
        guard let s = urlString, let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            // JRPlatformImage is UIImage on iOS, NSImage on macOS. Both accept
            // init(data:) and expose a `size` that MPMediaItemArtwork consumes.
            guard let data = data, let image = JRPlatformImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }

    private var lastTrackTitle: String?
    private var lastTrackArtist: String?

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

        // Keep lock-screen / CarPlay now-playing info in sync as new title
        // or artist frames arrive. HLS ID3 often sends TIT2 and TPE1 as
        // separate frames, so update-on-partial-change is expected.
        var nowPlayingDirty = false
        if let t = title, !t.isEmpty, t != lastTrackTitle {
            lastTrackTitle = t
            nowPlayingDirty = true
        }
        if let a = artist, !a.isEmpty, a != lastTrackArtist {
            lastTrackArtist = a
            nowPlayingDirty = true
        }
        if nowPlayingDirty { updateNowPlayingInfo() }

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
