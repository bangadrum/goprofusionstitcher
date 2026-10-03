import Foundation

/// Finds a per-clip yaw correction for the back eye by pixel-matching the
/// two seam overlap bands, rather than trusting the generic blog-derived
/// yaw=180 value exactly.
///
/// Why this helps: the Fusion's lenses are ~190° FOV, giving a ~10°-wide
/// band at each seam where *both* eyes see the same real-world content. If
/// front and back are perfectly calibrated, that content lines up exactly
/// when front is rendered at yaw 0 and back at yaw 180. In practice,
/// manufacturing tolerance on a specific physical unit can put that a
/// degree or so off, which shows up as a visible double-image at the seam
/// even for distant, static subjects.
///
/// This is a *global calibration* fix, not a parallax fix: it searches for
/// a single yaw rotation of the back eye that best aligns the two overlap
/// bands (scored by SSIM, ffmpeg's structural similarity filter), using one
/// representative frame. It will not remove ghosting caused by subjects
/// close to the camera near the seam — that's parallax (the two lenses are
/// physically offset by a few centimeters), and fixing *that* requires
/// per-frame optical-flow-based seam warping, which is a different, much
/// larger undertaking than this app currently does.
enum SeamCalibrator {
    static let searchRangeDegrees: ClosedRange<Double> = -5...5
    static let searchStepDegrees: Double = 0.5
    static let testWidth = 1600
    static let testHeight = 800
    static let bandPx = 50

    struct Result {
        let yawOffsetDegrees: Double
        let score: Double
    }

    static func calibrate(clip: Clip, mode: CameraMode) throws -> Result {
        guard let ffmpeg = ToolLocator.ffmpeg else { throw StitchError.ffmpegMissing }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoProFusionStitcher-calib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Sample a frame a little into the clip (avoids any black frames at
        // the very start) rather than frame zero.
        let testTime = min(1.0, (clip.durationSeconds ?? 2) / 2)

        let frontEq = workDir.appendingPathComponent("front.png")
        try renderEyeStill(
            ffmpeg: ffmpeg, source: clip.frontURL, time: testTime,
            radius: mode.frontRadius, center: mode.frontCenter, yaw: 0, out: frontEq
        )

        var best = Result(yawOffsetDegrees: 0, score: -1)
        var offset = searchRangeDegrees.lowerBound
        while offset <= searchRangeDegrees.upperBound {
            let backEq = workDir.appendingPathComponent("back_\(offset).png")
            try renderEyeStill(
                ffmpeg: ffmpeg, source: clip.backURL, time: testTime,
                radius: mode.backRadius, center: mode.backCenter,
                yaw: wrappedYaw(180 + offset), out: backEq
            )
            let score = try seamSimilarity(ffmpeg: ffmpeg, frontEq: frontEq, backEq: backEq)
            if score > best.score {
                best = Result(yawOffsetDegrees: offset, score: score)
            }
            offset += searchStepDegrees
        }
        return best
    }

    /// v360's yaw parameter must stay within [-180, 180]; wrap anything
    /// that overshoots back into range (180° and -180° are the same seam).
    static func wrappedYaw(_ raw: Double) -> Double {
        var y = raw
        while y > 180 { y -= 360 }
        while y < -180 { y += 360 }
        return y
    }

    private static func renderEyeStill(
        ffmpeg: URL, source: URL, time: Double,
        radius: Int, center: FisheyePoint, yaw: Double, out: URL
    ) throws {
        let padding = StitchFilterGraph.padding
        let cropSize = 2 * radius
        let cropX = center.x - radius + padding
        let cropY = center.y - radius + padding
        let filter = """
        pad=iw+\(2 * padding):ih+\(2 * padding):\(padding):\(padding):black,\
        crop=\(cropSize):\(cropSize):\(cropX):\(cropY),\
        v360=input=fisheye:output=e:ih_fov=190:iv_fov=190:yaw=\(yaw):w=\(testWidth):h=\(testHeight):interp=cubic
        """

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-y", "-ss", String(time), "-i", source.path, "-vf", filter, "-frames:v", "1", out.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            throw StitchError.maskRenderFailed(
                "seam calibration render failed: " + (String(data: data, encoding: .utf8) ?? "unknown error")
            )
        }
    }

    /// Crops both seam overlap bands out of each equirect still, stacks
    /// each pair side by side, and scores similarity with ffmpeg's ssim
    /// filter. Higher is better aligned.
    private static func seamSimilarity(ffmpeg: URL, frontEq: URL, backEq: URL) throws -> Double {
        let seam1 = Int(Double(testWidth) * 0.25) - bandPx
        let seam2 = Int(Double(testWidth) * 0.75) - bandPx
        let bandW = bandPx * 2

        let filter = """
        [0:v]crop=\(bandW):\(testHeight):\(seam1):0[a1];\
        [0:v]crop=\(bandW):\(testHeight):\(seam2):0[a2];\
        [a1][a2]hstack[a];\
        [1:v]crop=\(bandW):\(testHeight):\(seam1):0[b1];\
        [1:v]crop=\(bandW):\(testHeight):\(seam2):0[b2];\
        [b1][b2]hstack[b];\
        [a][b]ssim
        """

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-i", frontEq.path, "-i", backEq.path, "-lavfi", filter, "-f", "null", "-"]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let line = text.split(separator: "\n").last(where: { $0.contains("All:") }),
              let allRange = line.range(of: "All:") else {
            return -1
        }
        let after = line[allRange.upperBound...]
        let numberToken = after.split(separator: " ").first.map(String.init) ?? ""
        return Double(numberToken) ?? -1
    }
}
