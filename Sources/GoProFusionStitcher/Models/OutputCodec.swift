import Foundation

/// Delivery codecs offered in the UI. ProRes/DNxHR are the sensible defaults
/// for dropping straight into a DaVinci Resolve timeline for reframing;
/// H.264 is offered as a smaller, quicker-to-generate preview/proxy option.
enum OutputCodec: String, CaseIterable, Identifiable {
    case proRes422HQ = "Apple ProRes 422 HQ"
    case proRes422 = "Apple ProRes 422"
    case dnxhrHQ = "DNxHR HQ"
    case h264High = "H.264 (high bitrate, smaller file)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .proRes422HQ, .proRes422, .dnxhrHQ: return "mov"
        case .h264High: return "mp4"
        }
    }

    /// ffmpeg output arguments for video+audio encoding. Assumes the
    /// stitched, mapped video stream is the last thing before these args.
    func encodeArguments() -> [String] {
        switch self {
        case .proRes422HQ:
            return ["-c:v", "prores_ks", "-profile:v", "3", "-vendor", "apl0",
                    "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le"]
        case .proRes422:
            return ["-c:v", "prores_ks", "-profile:v", "2", "-vendor", "apl0",
                    "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le"]
        case .dnxhrHQ:
            return ["-c:v", "dnxhd", "-profile:v", "dnxhr_hq",
                    "-pix_fmt", "yuv422p", "-c:a", "pcm_s16le"]
        case .h264High:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "14",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k"]
        }
    }
}
