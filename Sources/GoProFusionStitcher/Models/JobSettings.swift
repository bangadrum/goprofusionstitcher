import Foundation
import Combine

final class JobSettings: ObservableObject {
    /// nil = use each clip's recommended width for its detected mode.
    @Published var customOutputWidth: Int? = nil
    /// Blend zone width, in degrees of longitude, either side of each seam.
    /// The Fusion's ~190° lens FOV gives a natural 5° overlap (Trek View part 4).
    @Published var blendDegrees: Double = 5.0
    @Published var codec: OutputCodec = .proRes422HQ
    @Published var embedSphericalMetadata: Bool = true
    @Published var outputFolder: URL? = nil
    @Published var interpolation: String = "cubic" // cubic | lanczos | linear

    func outputWidth(for mode: CameraMode) -> Int {
        customOutputWidth ?? mode.recommendedOutputWidth
    }

    /// Fusion's fisheye is exactly 2:1 once mapped to equirectangular
    /// (full 360° horizontal, 180° vertical), so height is always width/2.
    func outputHeight(for mode: CameraMode) -> Int {
        outputWidth(for: mode) / 2
    }
}
