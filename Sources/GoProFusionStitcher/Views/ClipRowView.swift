import SwiftUI

struct ClipRowView: View {
    @ObservedObject var clip: Clip
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.displayName)
                    .font(.system(.body, design: .monospaced))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingView
                .frame(width: 160, alignment: .trailing)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var subtitle: String {
        var parts: [String] = [clip.frontURL.lastPathComponent, clip.backURL.lastPathComponent]
        if let mode = clip.mode { parts.append(mode.label) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch clip.status {
        case .pending, .probing:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch clip.status {
        case .pending:
            Text("Pending").foregroundStyle(.secondary)
        case .probing:
            Text("Probing…").foregroundStyle(.secondary)
        case .ready:
            Text("Ready").foregroundStyle(.secondary)
        case .running(let progress):
            ProgressView(value: progress)
                .frame(width: 140)
        case .done(let url):
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.red)
                .help(message)
        }
    }
}
