import Foundation

enum ProbeError: Error, LocalizedError {
    case ffprobeMissing
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .ffprobeMissing:
            return "ffprobe not found. Install ffmpeg (which includes ffprobe), e.g. `brew install ffmpeg`."
        case .parseFailure(let raw):
            return "Could not parse ffprobe output: \(raw)"
        }
    }
}

struct ProbeResult {
    let width: Int
    let height: Int
    let durationSeconds: Double
    let hasAudio: Bool
}

enum Probe {
    static func run(on url: URL) throws -> ProbeResult {
        guard let ffprobe = ToolLocator.ffprobe else { throw ProbeError.ffprobeMissing }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1"
        ] + ["-i", url.path]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProbeError.parseFailure("<no output>")
        }

        var width: Int?
        var height: Int?
        var duration: Double?

        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "width": width = Int(parts[1])
            case "height": height = Int(parts[1])
            case "duration": duration = Double(parts[1])
            default: break
            }
        }

        guard let w = width, let h = height, let d = duration else {
            throw ProbeError.parseFailure(text)
        }

        let hasAudio = try hasAudioStream(url: url, ffprobe: ffprobe)
        return ProbeResult(width: w, height: h, durationSeconds: d, hasAudio: hasAudio)
    }

    private static func hasAudioStream(url: URL, ffprobe: URL) throws -> Bool {
        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index",
            "-of", "csv=p=0",
            "-i", url.path
        ]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
