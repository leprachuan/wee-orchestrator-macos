import SwiftUI

struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case paragraph(String)
        case code(language: String, content: String)
        case heading(level: Int, text: String)
        case listItem(text: String)
        case image(alt: String, url: URL)
    }

    private static let imagePattern = /!\[([^\]]*)\]\(([^)]+)\)/

    private var blocks: [Block] {
        var result: [Block] = []
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1
                result.append(.code(language: lang, content: codeLines.joined(separator: "\n")))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
                i += 1
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
                i += 1
            } else if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
                i += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.listItem(text: String(line.dropFirst(2))))
                i += 1
            } else if let match = line.wholeMatch(of: /^\d+\.\s+(.*)/) {
                result.append(.listItem(text: String(match.1)))
                i += 1
            } else {
                var para: [String] = []
                while i < lines.count &&
                      !lines[i].hasPrefix("```") &&
                      !lines[i].hasPrefix("# ") &&
                      !lines[i].hasPrefix("## ") &&
                      !lines[i].hasPrefix("### ") &&
                      !lines[i].hasPrefix("- ") &&
                      !lines[i].hasPrefix("* ") {
                    if lines[i].isEmpty && !para.isEmpty { break }
                    para.append(lines[i])
                    i += 1
                }
                let text = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append(contentsOf: splitImagesFromText(text))
                } else {
                    i += 1
                }
            }
        }
        return result
    }

    private func splitImagesFromText(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var remaining = text[text.startIndex...]

        while let match = remaining.firstMatch(of: Self.imagePattern) {
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                blocks.append(.paragraph(before))
            }

            let alt = String(match.1)
            let urlString = String(match.2)
            if let url = URL(string: urlString) {
                blocks.append(.image(alt: alt, url: url))
            } else {
                blocks.append(.paragraph("![\(alt)](\(urlString))"))
            }

            remaining = remaining[match.range.upperBound...]
        }

        let after = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty {
            blocks.append(.paragraph(after))
        }

        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdown(text)
                .textSelection(.enabled)

        case .code(_, let content):
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))

        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())

        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .foregroundStyle(WeeTheme.textMuted)
                inlineMarkdown(text)
            }

        case .image(let alt, let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
                case .failure:
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text(alt.isEmpty ? "Image failed to load" : alt)
                            .font(.caption)
                    }
                    .foregroundStyle(WeeTheme.textMuted)
                    .padding(8)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                default:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(alt.isEmpty ? "Loading image…" : alt)
                            .font(.caption)
                            .foregroundStyle(WeeTheme.textMuted)
                    }
                    .padding(8)
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        let cleaned = text.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        if let attributed = try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
                .font(.body)
                .foregroundColor(WeeTheme.textPrimary)
        }
        return Text(cleaned)
            .font(.body)
            .foregroundColor(WeeTheme.textPrimary)
    }
}
