import Foundation

/// Builds the ffmpeg filter_complex graph that turns a GPFR (front) + GPBK
/// (back) fisheye pair into one equirectangular frame.
///
/// The approach, matching the method built up across Trek View's "Stitching
/// GoPro Fusion Images Without GoPro Fusion Studio" series:
///
///   1. Each eye's fisheye circle is centered in a square crop (padding first
///      since the circle extends a little past the raw frame on some edges).
///   2. `v360` remaps each square fisheye (190° FOV, per Trek View part 3)
///      onto its own full equirectangular canvas — front centered at yaw 0,
///      back rotated to yaw 180 (Trek View part 4). Each eye's FOV exceeds
///      180°, so vertically the poles are already fully covered by a single
///      eye; horizontally the two eyes overlap by 5° at each of the two
///      seams (yaw ±90°).
///   3. A blend mask — full weight in the middle of each eye's coverage,
///      linearly feathered across the two 5°-wide seams — is used to alpha-
///      composite front over back, so the duplicate-pixel zones dissolve
///      smoothly instead of hard-cutting (Trek View part 4's "blend zone").
///
/// This was tested end-to-end against real GPFR/GPBK 5.2K sample footage
/// before being wired into the app.
enum StitchFilterGraph {
    static let padding = 50 // px of safety padding before cropping the fisheye circle

    /// The full filter_complex string. Inputs are assumed to be, in order:
    ///   0: front video, 1: back video, 2: blend mask image (looped still).
    static func build(mode: CameraMode, outputWidth: Int, outputHeight: Int, interpolation: String) -> String {
        let front = eyeFilter(
            inputLabel: "0:v", radius: mode.frontRadius, center: mode.frontCenter,
            frameW: mode.frameWidth, frameH: mode.frameHeight,
            yaw: 0, outputWidth: outputWidth, outputHeight: outputHeight,
            interpolation: interpolation, outLabel: "front"
        )
        let back = eyeFilter(
            inputLabel: "1:v", radius: mode.backRadius, center: mode.backCenter,
            frameW: mode.frameWidth, frameH: mode.frameHeight,
            yaw: 180, outputWidth: outputWidth, outputHeight: outputHeight,
            interpolation: interpolation, outLabel: "back"
        )

        let composite = """
        [2:v]scale=\(outputWidth):\(outputHeight)[mask];\
        [front][mask]alphamerge[fronta];\
        [back][fronta]overlay=0:0:format=auto[stitched]
        """

        return [front, back, composite].joined(separator: ";")
    }

    private static func eyeFilter(
        inputLabel: String, radius: Int, center: (x: Int, y: Int),
        frameW: Int, frameH: Int, yaw: Int,
        outputWidth: Int, outputHeight: Int, interpolation: String, outLabel: String
    ) -> String {
        let cropSize = 2 * radius
        let cropX = center.x - radius + padding
        let cropY = center.y - radius + padding

        return """
        [\(inputLabel)]pad=iw+\(2 * padding):ih+\(2 * padding):\(padding):\(padding):black,\
        crop=\(cropSize):\(cropSize):\(cropX):\(cropY),\
        v360=input=fisheye:output=e:ih_fov=190:iv_fov=190:yaw=\(yaw):w=\(outputWidth):h=\(outputHeight):interp=\(interpolation),\
        format=yuv420p[\(outLabel)]
        """
    }

    /// Builds the standalone ffmpeg command (as a lavfi source) that renders
    /// the seam blend mask to a single PNG. Full front weight (255) across
    /// the middle of each eye's coverage, linearly feathered to 0 across the
    /// two seams (at yaw ±90°) over `blendDegrees` on each side, matching
    /// fusion2sphere's `-b` blend-zone flag.
    static func maskGeqExpression(outputWidth: Int, blendDegrees: Double) -> String {
        let band = Double(outputWidth) * blendDegrees / 360.0
        let seamLeft = Double(outputWidth) * 0.25
        let seamRight = Double(outputWidth) * 0.75

        // Escaped commas (\,) are required because ffmpeg's filtergraph
        // parser treats bare commas as filter separators.
        return """
        if(lt(X\\,\(seamLeft - band))\\,0\\,\
        if(lt(X\\,\(seamLeft + band))\\,255*(X-(\(seamLeft - band)))/(2*\(band))\\,\
        if(lt(X\\,\(seamRight - band))\\,255\\,\
        if(lt(X\\,\(seamRight + band))\\,255*(1-(X-(\(seamRight - band)))/(2*\(band)))\\,0))))
        """
    }
}
