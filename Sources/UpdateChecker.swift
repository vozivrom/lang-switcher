import Foundation

/// Asks GitHub whether a newer release exists.
///
/// Only checks — it doesn't download or install anything. Replacing the app in
/// place would mean running code fetched from the network, and the only way to
/// do that safely is to verify the download carries our code-signing
/// certificate. Releases are ad-hoc signed today, so there's nothing to pin
/// against and the user installs the update themselves.
enum UpdateChecker {

    private static let releasesAPI =
        URL(string: "https://api.github.com/repos/vozivrom/lang-switcher/releases/latest")!

    static let releasesPage =
        URL(string: "https://github.com/vozivrom/lang-switcher/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Calls back on the main queue with the newer version, or nil if this is
    /// already the latest (or the check failed — a missed check is not worth
    /// bothering the user about).
    static func check(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let latest = data.flatMap(parseTag)
            let newer = latest.flatMap { isNewer($0, than: currentVersion) ? $0 : nil }
            DispatchQueue.main.async { completion(newer) }
        }.resume()
    }

    private static func parseTag(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compares dotted version numbers a component at a time, so 1.10.0 beats
    /// 1.9.0 — which a string comparison would get wrong.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
