import CommonCrypto
import Foundation

/// Native Last.fm client used when Flutter isn't active — CarPlay's
/// likeCommand handlers and the background track-change hook call here
/// so the loved-track state stays live without a running Dart engine.
///
/// Mirrors the Dart LastfmRepository for track.love / track.unlove /
/// track.getInfo. Signing is MD5 over alphabetically-sorted key+value
/// pairs followed by the shared secret, matching the Android/Dart
/// implementations.
///
/// All requests use URLSession.shared; completions run on
/// DispatchQueue.main unless otherwise noted.
enum LastfmClient {
    static let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    struct Creds {
        let apiKey: String
        let apiSecret: String
        let sessionKey: String
    }

    static func loveTrack(
        artist: String,
        title: String,
        creds: Creds,
        completion: @escaping (Bool) -> Void
    ) {
        signedPost(method: "track.love", artist: artist, title: title,
                   creds: creds, completion: completion)
    }

    static func unloveTrack(
        artist: String,
        title: String,
        creds: Creds,
        completion: @escaping (Bool) -> Void
    ) {
        signedPost(method: "track.unlove", artist: artist, title: title,
                   creds: creds, completion: completion)
    }

    /// Unauth'd lookup: has `username` loved this track? Completes with
    /// false on any failure, including unknown tracks.
    static func isTrackLoved(
        artist: String,
        title: String,
        username: String,
        apiKey: String,
        completion: @escaping (Bool) -> Void
    ) {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "method", value: "track.getInfo"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "track", value: title),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = comps.url else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let loved: Bool = {
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let track = obj["track"] as? [String: Any]
                else { return false }
                // userloved arrives as "0" or "1" — treat anything non-"1" as false.
                if let s = track["userloved"] as? String { return s == "1" }
                if let n = track["userloved"] as? Int { return n == 1 }
                return false
            }()
            DispatchQueue.main.async { completion(loved) }
        }.resume()
    }

    private static func signedPost(
        method: String,
        artist: String,
        title: String,
        creds: Creds,
        completion: @escaping (Bool) -> Void
    ) {
        // Sign the six canonical params (no format) — Last.fm computes
        // api_sig from the same sorted key+value concat.
        let signParams: [String: String] = [
            "api_key": creds.apiKey,
            "artist": artist,
            "method": method,
            "sk": creds.sessionKey,
            "track": title,
        ]
        let signature = signLastfm(params: signParams, secret: creds.apiSecret)

        var body = signParams
        body["api_sig"] = signature
        body["format"] = "json"
        let payload = formUrlEncode(body)

        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            // Last.fm returns 200 even on API errors; we must parse the body.
            let success: Bool = {
                guard (200...299).contains(code) else { return false }
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                if let apiError = obj["error"] as? Int, apiError != 0 { return false }
                return true
            }()
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }

    private static func signLastfm(params: [String: String], secret: String) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        var s = ""
        for (k, v) in sorted {
            s.append(k)
            s.append(v)
        }
        s.append(secret)
        return md5Hex(s)
    }

    private static func md5Hex(_ input: String) -> String {
        let data = input.data(using: .utf8) ?? Data()
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func formUrlEncode(_ params: [String: String]) -> String {
        // URLComponents gives correct x-www-form-urlencoded encoding when
        // we pull the percent-encoded query out of a built-up URL.
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery ?? ""
    }
}
