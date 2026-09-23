import Foundation

enum ClipPairer {
    /// Fusion video files are named GPFR#### / GPBK#### (front/back) where
    /// #### is a shared take number. We match case-insensitively and allow
    /// either .MP4 or .mp4.
    private static func takeNumber(of url: URL, prefix: String) -> String? {
        let name = url.deletingPathExtension().lastPathComponent.uppercased()
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard !rest.isEmpty, rest.allSatisfy({ $0.isNumber }) else { return nil }
        return String(rest)
    }

    /// Recursively expands folders into candidate .MP4 files.
    private static func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let file as URL in enumerator
                    where file.pathExtension.uppercased() == "MP4" {
                        result.append(file)
                    }
                }
            } else if url.pathExtension.uppercased() == "MP4" {
                result.append(url)
            }
        }
        return result
    }

    /// Pairs up front/back files found among `inputs` (files and/or folders).
    /// Files that can't be paired are reported separately so the UI can warn
    /// about them rather than silently dropping footage.
    static func pair(_ inputs: [URL]) -> (clips: [Clip], unmatched: [URL]) {
        let files = expand(inputs)

        var fronts: [String: URL] = [:]
        var backs: [String: URL] = [:]

        for file in files {
            if let take = takeNumber(of: file, prefix: "GPFR") {
                fronts[take] = file
            } else if let take = takeNumber(of: file, prefix: "GPBK") {
                backs[take] = file
            }
        }

        var clips: [Clip] = []
        var unmatched: [URL] = []

        for (take, frontURL) in fronts.sorted(by: { $0.key < $1.key }) {
            if let backURL = backs[take] {
                clips.append(Clip(frontURL: frontURL, backURL: backURL, takeNumber: take))
                backs.removeValue(forKey: take)
            } else {
                unmatched.append(frontURL)
            }
        }
        unmatched.append(contentsOf: backs.values)

        return (clips, unmatched)
    }
}
