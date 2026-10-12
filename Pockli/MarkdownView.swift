import SwiftUI
import Textual

/// Renders a model reply as Markdown: headings, lists, tables, quotes and
/// syntax-highlighted code blocks with a Copy button.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        StructuredText(markdown: markdown)
            .textual.structuredTextStyle(.gitHub)
            .textual.codeBlockStyle(CodeCardStyle())
            .textual.textSelection(.enabled)
    }
}

/// A code block as a card: language label and Copy button on top, code below
/// (scrolls sideways for long lines).
struct CodeCardStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        CodeCard(configuration: configuration)
    }
}

private struct CodeCard: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.languageHint?.lowercased() ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    configuration.codeBlock.copyToPasteboard()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            Overflow {
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.225))
                    .textual.fontScale(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(14)
            }
        }
        .background(Color(.secondarySystemBackground).opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.5))
        }
        .textual.blockSpacing(.init(top: 4, bottom: 14))
    }
}
