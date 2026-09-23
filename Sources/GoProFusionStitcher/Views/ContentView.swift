import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedClip: Clip?
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if let warning = model.toolWarning {
                    warningBanner(warning)
                }

                if model.clips.isEmpty {
                    dropZone
                } else {
                    List(selection: $selectedClip) {
                        ForEach(model.clips) { clip in
                            ClipRowView(clip: clip) { model.remove(clip) }
                                .tag(clip)
                        }
                    }
                    .listStyle(.inset)
                }

                if !model.unmatchedFiles.isEmpty {
                    unmatchedBanner
                }

                Divider()
                toolbar
            }
            .navigationSplitViewColumnWidth(min: 460, ideal: 560)
        } detail: {
            HSplitView {
                SettingsView(settings: model.settings)
                    .frame(minWidth: 320, idealWidth: 340)

                logPanel
                    .frame(minWidth: 260)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: - Subviews

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop GPFR/GPBK video files or a folder here")
                .font(.headline)
            Text("Front and back files are paired automatically by their take number (e.g. GPFR0118.MP4 + GPBK0118.MP4).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Add Files…") { chooseFiles() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var toolbar: some View {
        HStack {
            Button("Add Files…") { chooseFiles() }
            Button("Add Folder…") { chooseFolder() }
            Spacer()
            if !model.clips.isEmpty {
                Button("Clear", role: .destructive) { model.clearAll() }
            }
            Button {
                model.runQueue()
            } label: {
                if model.isRunning {
                    Label("Stitching…", systemImage: "hourglass")
                } else {
                    Label("Stitch All", systemImage: "play.fill")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isRunning || model.clips.isEmpty || ToolLocator.ffmpeg == nil)
        }
        .padding(10)
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }

    private var unmatchedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            Text("\(model.unmatchedFiles.count) file(s) couldn't be paired (missing front or back match).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selectedClip.map { "Log — \($0.displayName)" } ?? "Select a clip to view its log")
                .font(.headline)
                .padding(10)
            Divider()
            ScrollView {
                Text(selectedClip?.log ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }

    // MARK: - Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mpeg4Movie, .movie]
        if panel.runModal() == .OK {
            model.addInputs(panel.urls)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.addInputs([url])
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty { model.addInputs(urls) }
        }
        return true
    }
}
