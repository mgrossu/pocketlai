import SwiftUI
import Textual

/// Renders a model reply as Markdown: headings, lists, tables, quotes, LaTeX math and
/// syntax-highlighted code blocks with a Copy button.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        let (text, hasMath) = LaTeX.normalize(markdown)
        StructuredText(markdown: text, syntaxExtensions: hasMath ? [.math] : [])
            // The modifier closest to the view wins, so the card style goes first;
            // otherwise the GitHub preset's own code block style replaces it.
            .textual.codeBlockStyle(CodeCardStyle())
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
    }
}

/// Rewrites the LaTeX notation models use into the notation Textual renders.
///
/// Models write display math as `\[ … \]` or `$$ … $$` and inline math as `\( … \)`.
/// Markdown parsing strips backslashes before punctuation (`\[` → `[`, `\,` → `,`), so:
/// - display math becomes a fenced ```` ```math ```` block, which keeps its text verbatim;
/// - inline math becomes `$ … $`, with backslashes before punctuation doubled so they survive.
/// Code blocks are left untouched.
enum LaTeX {
    static func normalize(_ markdown: String) -> (text: String, hasMath: Bool) {
        guard markdown.contains("\\[") || markdown.contains("\\(") || markdown.contains("$") else {
            return (markdown, false)
        }
        var output: [String] = []
        var prose: [String] = []
        var inFence = false
        var hasMath = false

        func flushProse() {
            guard !prose.isEmpty else { return }
            let (converted, found) = convert(prose.joined(separator: "\n"))
            output.append(converted)
            hasMath = hasMath || found
            prose.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !inFence { flushProse() }
                inFence.toggle()
                if line.trimmingCharacters(in: .whitespaces).lowercased() == "```math" { hasMath = true }
                output.append(line)
            } else if inFence {
                output.append(line)
            } else {
                prose.append(line)
            }
        }
        flushProse()
        return (output.joined(separator: "\n"), hasMath)
    }

    private static func convert(_ text: String) -> (String, Bool) {
        var found = false
        var text = text
        // Display math → ```math fence on its own lines.
        for pattern in [#"\\\[(.+?)\\\]"#, #"\$\$(.+?)\$\$"#] {
            text = replace(pattern, in: text) { latex in
                found = true
                return "\n```math\n\(latex.trimmingCharacters(in: .whitespacesAndNewlines))\n```\n"
            }
        }
        // Inline \( … \) → $ … $.
        text = replace(#"\\\((.+?)\\\)"#, in: text) { latex in
            found = true
            return "$\(protect(latex.trimmingCharacters(in: .whitespaces)))$"
        }
        // Existing $ … $ that contains a LaTeX command (not prices like "$5 and $10").
        text = replace(#"(?<!\$)\$([^$\n]*\\[A-Za-z][^$\n]*)\$(?!\$)"#, in: text) { latex in
            found = true
            return "$\(protect(latex))$"
        }
        return (text, found)
    }

    /// Doubles backslashes before ASCII punctuation, which Markdown would otherwise consume.
    private static func protect(_ latex: String) -> String {
        replace(#"\\([!-/:-@\[-`{-~])"#, in: latex, multiline: false) { char in "\\\\" + char }
    }

    /// Replaces each match of `pattern`, passing capture group 1 to `transform`.
    private static func replace(
        _ pattern: String, in text: String, multiline: Bool = true, _ transform: (String) -> String
    ) -> String {
        let options: NSRegularExpression.Options = multiline ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let source = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            result += transform(source.substring(with: match.range(at: 1)))
            location = match.range.location + match.range.length
        }
        result += source.substring(from: location)
        return result
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
