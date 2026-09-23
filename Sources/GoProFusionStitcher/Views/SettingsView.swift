import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: JobSettings

    var body: some View {
        Form {
            Section("Output") {
                Picker("Codec", selection: $settings.codec) {
                    ForEach(OutputCodec.allCases) { codec in
                        Text(codec.rawValue).tag(codec)
                    }
                }
                Text(codecHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Output folder")
                    Spacer()
                    Button(settings.outputFolder?.lastPathComponent ?? "Same as source") {
                        chooseOutputFolder()
                    }
                }
            }

            Section("Stitching") {
                Picker("Output width", selection: Binding(
                    get: { settings.customOutputWidth ?? 0 },
                    set: { settings.customOutputWidth = $0 == 0 ? nil : $0 }
                )) {
                    Text("Recommended for mode").tag(0)
                    Text("3072 (3K)").tag(3072)
                    Text("3840 (4K)").tag(3840)
                    Text("5228 (5.2K)").tag(5228)
                    Text("5760 (5.7K)").tag(5760)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Seam blend width")
                        Spacer()
                        Text("\(settings.blendDegrees, specifier: "%.1f")°")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.blendDegrees, in: 1...10, step: 0.5)
                }
                Text("The Fusion's lenses overlap by about 5° on each seam. Increase this if a seam still looks hard; decrease it if moving subjects ghost in the overlap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Interpolation", selection: $settings.interpolation) {
                    Text("Cubic (recommended)").tag("cubic")
                    Text("Lanczos (sharper, slower)").tag("lanczos")
                    Text("Linear (fastest)").tag("linear")
                }
            }

            Section("Metadata") {
                Toggle("Embed spherical (360°) metadata", isOn: $settings.embedSphericalMetadata)
                Text("Tags the output so Resolve, QuickTime, and other 360 players recognize it automatically. Requires exiftool (`brew install exiftool`); safe to leave on even if it's not installed — stitching still succeeds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var codecHint: String {
        switch settings.codec {
        case .proRes422HQ, .proRes422:
            return "Best choice for reframing in DaVinci Resolve. Large files."
        case .dnxhrHQ:
            return "Good alternative to ProRes, especially outside Apple hardware."
        case .h264High:
            return "Much smaller, quicker to generate — fine for previews, but re-encode for a final grade."
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            settings.outputFolder = panel.url
        }
    }
}
