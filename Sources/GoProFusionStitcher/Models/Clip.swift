import Foundation

enum ClipStatus: Equatable {
    case pending
    case probing
    case ready
    case running(progress: Double)
    case done(outputURL: URL)
    case failed(message: String)

    var sortWeight: Int {
        switch self {
        case .failed: return 0
        case .running: return 1
        case .pending, .probing: return 2
        case .ready: return 3
        case .done: return 4
        }
    }
}

/// A matched front+back pair of GoPro Fusion files, plus everything learned
/// about them (resolution, detected camera mode) and their processing state.
final class Clip: Identifiable, ObservableObject, Equatable, Hashable {
    let id = UUID()
    let frontURL: URL
    let backURL: URL
    /// The shared take number used to pair the files, e.g. "0118".
    let takeNumber: String

    @Published var mode: CameraMode?
    @Published var durationSeconds: Double?
    @Published var status: ClipStatus = .pending
    @Published var log: String = ""

    init(frontURL: URL, backURL: URL, takeNumber: String) {
        self.frontURL = frontURL
        self.backURL = backURL
        self.takeNumber = takeNumber
    }

    var displayName: String { "GP\(takeNumber)" }

    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func appendLog(_ line: String) {
        DispatchQueue.main.async {
            self.log += line + "\n"
        }
    }
}
