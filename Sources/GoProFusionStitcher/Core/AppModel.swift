import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var unmatchedFiles: [URL] = []
    @Published var isRunning = false
    @Published var toolWarning: String? = nil

    let settings = JobSettings()
    private let engine = StitchEngine()

    init() {
        checkTools()
    }

    func checkTools() {
        if ToolLocator.ffmpeg == nil {
            toolWarning = "ffmpeg was not found on this Mac. Install it (e.g. `brew install ffmpeg`) " +
                          "before stitching — the app can still add and inspect clips without it."
        } else {
            toolWarning = nil
        }
    }

    func addInputs(_ urls: [URL]) {
        let (newClips, unmatched) = ClipPairer.pair(urls)
        // Skip take numbers we already have queued.
        let existingTakes = Set(clips.map { $0.takeNumber })
        let toAdd = newClips.filter { !existingTakes.contains($0.takeNumber) }
        clips.append(contentsOf: toAdd)
        unmatchedFiles.append(contentsOf: unmatched)

        for clip in toAdd {
            probeClip(clip)
        }
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
    }

    func clearAll() {
        clips.removeAll()
        unmatchedFiles.removeAll()
    }

    private func probeClip(_ clip: Clip) {
        clip.status = .probing
        Task.detached { [engine] in
            do {
                try engine.probe(clip)
                await MainActor.run { clip.status = .ready }
            } catch {
                await MainActor.run { clip.status = .failed(message: error.localizedDescription) }
            }
        }
    }

    /// Runs every `.ready` (or previously `.failed`) clip in the queue, one
    /// at a time — ffmpeg already saturates available cores per job, so
    /// running clips in parallel would only add contention.
    func runQueue() {
        guard !isRunning else { return }
        isRunning = true
        Task.detached { [weak self] in
            guard let self else { return }
            let queue = await MainActor.run {
                self.clips.filter {
                    if case .ready = $0.status { return true }
                    if case .failed = $0.status { return true }
                    return false
                }
            }
            for clip in queue {
                await self.process(clip)
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    /// Deliberately `nonisolated`: this performs the blocking ffmpeg
    /// invocation (via `engine.run`, which calls `Process.waitUntilExit`)
    /// and must not run on the main actor, or the UI would freeze for the
    /// duration of the encode. Only the small state mutations inside hop
    /// back to the main actor via `MainActor.run`.
    nonisolated private func process(_ clip: Clip) async {
        await MainActor.run { clip.status = .running(progress: 0) }
        do {
            let output = try engine.run(clip: clip, settings: settings) { fraction in
                clip.status = .running(progress: fraction)
            }
            await MainActor.run { clip.status = .done(outputURL: output) }
        } catch {
            await MainActor.run { clip.status = .failed(message: error.localizedDescription) }
        }
    }
}
