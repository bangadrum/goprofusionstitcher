import Foundation

/// Finds command-line tools this app shells out to. We don't bundle ffmpeg
/// (it's a large, license-encumbered binary); instead we look in the usual
/// Homebrew locations and the user's PATH, the same way most macOS media
/// tools do.
enum ToolLocator {
    private static let searchPaths = [
        "/opt/homebrew/bin",   // Apple Silicon Homebrew
        "/usr/local/bin",      // Intel Homebrew
        "/opt/local/bin",      // MacPorts
    ]

    static func find(_ toolName: String) -> URL? {
        let fm = FileManager.default

        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(toolName)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // Fall back to whatever the user's shell PATH resolves, by asking
        // /usr/bin/env (works for anyone who installed ffmpeg some other way).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", toolName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        } catch {
            return nil
        }
        return nil
    }

    static var ffmpeg: URL? { find("ffmpeg") }
    static var ffprobe: URL? { find("ffprobe") }
    static var exiftool: URL? { find("exiftool") }
}
