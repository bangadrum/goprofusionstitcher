import Foundation

enum StitchError: Error, LocalizedError {
    case ffmpegMissing
    case unsupportedResolution(width: Int, height: Int)
    case maskRenderFailed(String)
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "ffmpeg not found. Install it with `brew install ffmpeg`."
        case .unsupportedResolution(let w, let h):
            return "Unrecognized frame size \(w)×\(h). This doesn't match a known GoPro Fusion " +
                   "video mode (3K: 1568×1504, 5.2K: 2704×2624). Is this really a Fusion GPFR/GPBK file?"
        case .maskRenderFailed(let msg):
            return "Failed to render the seam blend mask: \(msg)"
        case .ffmpegFailed(let msg):
            return "ffmpeg failed:\n\(msg)"
        }
    }
}

final class StitchEngine {
    private var maskCache: [String: URL] = [:]
    private let maskCacheDir: URL

    init() {
        maskCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoProFusionStitcher-masks", isDirectory: true)
        try? FileManager.default.createDirectory(at: maskCacheDir, withIntermediateDirectories: true)
    }

    /// Probes both files, determines the camera mode, and stores it on the clip.
    func probe(_ clip: Clip) throws {
        let frontProbe = try Probe.run(on: clip.frontURL)
        guard let mode = CameraMode.match(width: frontProbe.width, height: frontProbe.height) else {
            throw StitchError.unsupportedResolution(width: frontProbe.width, height: frontProbe.height)
        }
        DispatchQueue.main.async {
            clip.mode = mode
            clip.durationSeconds = frontProbe.durationSeconds
        }
    }

    /// Renders (or reuses a cached) seam blend mask PNG for the given output size/blend.
    private func maskURL(outputWidth: Int, outputHeight: Int, blendDegrees: Double) throws -> URL {
        let key = "\(outputWidth)x\(outputHeight)_\(blendDegrees)"
        if let cached = maskCache[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let ffmpeg = ToolLocator.ffmpeg else { throw StitchError.ffmpegMissing }

        let url = maskCacheDir.appendingPathComponent("mask_\(key).png")
        let expr = StitchFilterGraph.maskGeqExpression(outputWidth: outputWidth, blendDegrees: blendDegrees)
        let source = "nullsrc=size=\(outputWidth)x\(outputHeight):duration=1:rate=1," +
                     "geq=lum='\(expr)':cb=128:cr=128,format=gray"

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-y", "-f", "lavfi", "-i", source, "-frames:v", "1", url.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            throw StitchError.maskRenderFailed(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        maskCache[key] = url
        return url
    }

    /// Runs the full stitch for one clip, reporting progress via `onProgress`
    /// (0...1) on the main queue. Throws on failure; returns the output URL
    /// on success.
    func run(clip: Clip, settings: JobSettings, onProgress: @escaping (Double) -> Void) throws -> URL {
        guard let ffmpeg = ToolLocator.ffmpeg else { throw StitchError.ffmpegMissing }
        guard let mode = clip.mode else {
            throw StitchError.unsupportedResolution(width: 0, height: 0)
        }

        let outW = settings.outputWidth(for: mode)
        let outH = settings.outputHeight(for: mode)
        let mask = try maskURL(outputWidth: outW, outputHeight: outH, blendDegrees: settings.blendDegrees)

        let filterGraph = StitchFilterGraph.build(
            mode: mode, outputWidth: outW, outputHeight: outH, interpolation: settings.interpolation
        )

        let outputFolder = settings.outputFolder ?? clip.frontURL.deletingLastPathComponent()
        let outputURL = outputFolder
            .appendingPathComponent("\(clip.displayName)_360")
            .appendingPathExtension(settings.codec.fileExtension)

        var hasAudio = false
        if let probe = try? Probe.run(on: clip.frontURL) { hasAudio = probe.hasAudio }

        var args: [String] = [
            "-y",
            "-i", clip.frontURL.path,
            "-i", clip.backURL.path,
            "-loop", "1", "-i", mask.path,
            "-filter_complex", filterGraph,
            "-map", "[stitched]"
        ]
        if hasAudio { args += ["-map", "0:a"] }
        args += settings.codec.encodeArguments()
        args += ["-shortest", "-progress", "pipe:1", "-nostats", "-loglevel", "error"]
        args += [outputURL.path]

        clip.appendLog("$ ffmpeg " + args.joined(separator: " "))

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stderrText = ""
        let stderrLock = NSLock()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stderrLock.lock()
            stderrText += text
            stderrLock.unlock()
            clip.appendLog(text.trimmingCharacters(in: .newlines))
        }

        let durationSeconds = clip.durationSeconds ?? 1
        var buffer = ""
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            let endsWithNewline = buffer.hasSuffix("\n")
            var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            // Keep a trailing partial line (no newline yet) for the next chunk.
            buffer = endsWithNewline ? "" : String(lines.removeLast())
            for line in lines {
                guard line.hasPrefix("out_time_ms=") || line.hasPrefix("out_time_us=") else { continue }
                let valueString = line.split(separator: "=", maxSplits: 1)[1]
                guard let micros = Double(valueString) else { continue }
                let seconds = micros / 1_000_000
                let fraction = durationSeconds > 0 ? min(max(seconds / durationSeconds, 0), 1) : 0
                DispatchQueue.main.async { onProgress(fraction) }
            }
        }

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            stderrLock.lock()
            let finalStderr = stderrText
            stderrLock.unlock()
            throw StitchError.ffmpegFailed(finalStderr.isEmpty ? "ffmpeg exited with status \(process.terminationStatus)" : finalStderr)
        }

        if settings.embedSphericalMetadata {
            if let warning = SphericalMetadata.embed(in: outputURL) {
                clip.appendLog("⚠️ " + warning)
            }
        }

        DispatchQueue.main.async { onProgress(1.0) }
        return outputURL
    }
}
