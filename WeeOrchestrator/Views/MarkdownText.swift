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
        case text(String)
        case code(language: String, content: String)
        case heading(level: Int, text: String)
        case listItem(text: String)
        case table(headers: [String], rows: [[String]])
        case image(alt: String, url: URL)
    }

    private static let imagePattern = /!\[([^\]]*)\]\(([^)]+)\)/

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
            } else if isTableStart(at: i, in: lines) {
                let headers = splitTableRow(lines[i])
                var rows: [[String]] = []
                i += 2
                while i < lines.count && isTableRow(lines[i]) {
                    rows.append(splitTableRow(lines[i]))
                    i += 1
                }
                result.append(.table(headers: headers, rows: rows))
            } else {
                var para: [String] = []
                while i < lines.count &&
                      !lines[i].hasPrefix("```") &&
                      !lines[i].hasPrefix("# ") &&
                      !lines[i].hasPrefix("## ") &&
                      !lines[i].hasPrefix("### ") &&
                      !lines[i].hasPrefix("- ") &&
                      !lines[i].hasPrefix("* ") &&
                      lines[i].wholeMatch(of: /^\d+\.\s+(.*)/) == nil &&
                      !isTableStart(at: i, in: lines) {
                    if lines[i].isEmpty && !para.isEmpty { break }
                    para.append(lines[i])
                    i += 1
                }
                let text = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append(contentsOf: extractImages(from: text))
                } else {
                    i += 1
                }
            }
        }
        return result
    }

    private func isTableStart(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let headers = splitTableRow(lines[index])
        guard headers.count >= 2 else { return false }
        return isTableSeparator(lines[index + 1])
    }

    private func isTableRow(_ line: String) -> Bool {
        splitTableRow(line).count >= 2
    }

    private func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private func extractImages(from text: String) -> [Block] {
        var blocks: [Block] = []
        var remaining = text[text.startIndex...]

        while let match = remaining.firstMatch(of: Self.imagePattern) {
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                blocks.append(.text(before))
            }

            let alt = String(match.1)
            let urlString = String(match.2)
            if let url = URL(string: urlString) {
                blocks.append(.image(alt: alt, url: url))
            }

            remaining = remaining[match.range.upperBound...]
        }

        let after = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty {
            blocks.append(.text(after))
        }

        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let text):
            renderInline(text)
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
            renderInline(stripImageSyntax(text))
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())

        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .foregroundStyle(WeeTheme.textMuted)
                renderInline(stripImageSyntax(text))
            }

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

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

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, columnCount: columnCount, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, columnCount: columnCount, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
        }
        .scrollIndicators(.hidden)
    }

    private func tableRow(_ cells: [String], columnCount: Int, isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { column in
                renderInline(column < cells.count ? cells[column] : "")
                    .font(isHeader ? .caption.bold() : .caption)
                    .frame(minWidth: 120, maxWidth: 240, alignment: .leading)
                    .padding(8)
                    .background(isHeader ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(Rectangle().stroke(WeeTheme.glassStroke.opacity(0.7)))
            }
        }
    }

    private func stripImageSyntax(_ text: String) -> String {
        text.replacing(Self.imagePattern, with: { match in String(match.1) })
    }

    private func renderInline(_ text: String) -> Text {
        let cleaned = stripImageSyntax(text)
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
