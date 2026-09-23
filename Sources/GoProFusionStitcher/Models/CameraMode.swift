import Foundation

/// Describes the fisheye circle geometry for one Fusion capture mode.
///
/// Values are taken from Trek View's "Stitching GoPro Fusion Images Without
/// GoPro Fusion Studio" series (parts 1-4), cross-checked against
/// fusion2sphere's parameter files, and re-verified in this project against
/// real GPFR/GPBK sample footage before shipping.
struct CameraMode: Equatable {
    /// Raw frame size as decoded from the source file.
    let frameWidth: Int
    let frameHeight: Int

    /// Fisheye circle radius (px) and center (px) for the front (GPFR) eye.
    let frontRadius: Int
    let frontCenter: (x: Int, y: Int)

    /// Fisheye circle radius (px) and center (px) for the back (GPBK) eye.
    let backRadius: Int
    let backCenter: (x: Int, y: Int)

    /// Horizontal/vertical field of view of each lens, in degrees.
    /// The Fusion's two lenses are ~190° each, giving a 5° overlap on each seam.
    let fovDegrees: Double = 190

    /// Recommended equirectangular output width for this mode (GoPro Fusion
    /// Studio's own defaults, per Trek View part 4).
    let recommendedOutputWidth: Int

    let label: String

    static let video5_2k = CameraMode(
        frameWidth: 2704, frameHeight: 2624,
        frontRadius: 1335, frontCenter: (1345, 1303),
        backRadius: 1338, backCenter: (1337, 1303),
        recommendedOutputWidth: 3840,
        label: "5.2K video (2704×2624 per eye)"
    )

    static let video3k = CameraMode(
        frameWidth: 1568, frameHeight: 1504,
        frontRadius: 765, frontCenter: (779, 742),
        backRadius: 765, backCenter: (779, 742),
        recommendedOutputWidth: 3072,
        label: "3K video (1568×1504 per eye)"
    )

    /// Picks the mode matching a probed frame size, if any.
    static func match(width: Int, height: Int) -> CameraMode? {
        for mode in [video5_2k, video3k] where mode.frameWidth == width && mode.frameHeight == height {
            return mode
        }
        return nil
    }
}
