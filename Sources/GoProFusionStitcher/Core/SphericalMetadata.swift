import Foundation

/// Tags an equirectangular output file as spherical (360°) video using the
/// same XMP-GSpherical fields Google's Spatial Media Metadata Injector and
/// YouTube's 360 uploader use. DaVinci Resolve, QuickTime 360 viewers, and
/// most 360 players pick this up automatically and switch to a pannable /
/// reframable view instead of showing the raw flat equirectangular image.
///
/// This is optional: reframing a flat equirectangular clip in Resolve's
/// standard tools (e.g. the 360 reframe / Fusion 3D transform) works fine
/// without this metadata too, and requires the file to be untouched, so we
/// only need it if it changes how the file is *read*, not how it's edited.
enum SphericalMetadata {
    /// Returns nil on success, or a human-readable warning string if
    /// exiftool wasn't available (stitching itself still succeeded).
    @discardableResult
    static func embed(in fileURL: URL) -> String? {
        guard let exiftool = ToolLocator.exiftool else {
            return "exiftool not found — spherical metadata was not embedded. " +
                   "Install it with `brew install exiftool` to enable this, or set the clip to " +
                   "equirectangular/360 manually in Resolve."
        }

        let process = Process()
        process.executableURL = exiftool
        process.arguments = [
            "-XMP-GSpherical:Spherical=True",
            "-XMP-GSpherical:Stitched=True",
            "-XMP-GSpherical:StitchingSoftware=GoProFusionStitcher",
            "-XMP-GSpherical:ProjectionType=equirectangular",
            "-XMP-GSpherical:SourceCount=2",
            "-overwrite_original",
            fileURL.path
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8) ?? "unknown exiftool error"
                return "exiftool reported an error while embedding metadata: \(msg)"
            }
        } catch {
            return "Failed to run exiftool: \(error.localizedDescription)"
        }
        return nil
    }
}
