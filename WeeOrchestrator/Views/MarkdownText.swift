import SwiftUI

struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case paragraph(String)
        case heading(level: Int, text: String)
        case list(items: [ListItem], ordered: Bool)
        case blockquote(String)
        case code(language: String, content: String)
        case table(headers: [String], rows: [[String]])
        case image(alt: String, url: URL)
        case horizontalRule
    }

    private struct ListItem {
        let text: String
        let depth: Int
        let checked: Bool?
    }

    private static let imagePattern = /!\[([^\]]*)\]\(([^)]+)\)/

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
            } else if isFence(trimmed) {
                result.append(parseCode(lines: lines, index: &i))
            } else if let heading = parseHeading(trimmed) {
                result.append(.heading(level: heading.level, text: heading.text))
                i += 1
            } else if isHorizontalRule(trimmed) {
                result.append(.horizontalRule)
                i += 1
            } else if isTableStart(at: i, in: lines) {
                result.append(parseTable(lines: lines, index: &i))
            } else if isListLine(line) {
                result.append(parseList(lines: lines, index: &i))
            } else if isBlockquoteLine(line) {
                result.append(parseBlockquote(lines: lines, index: &i))
            } else {
                let paragraph = parseParagraph(lines: lines, index: &i)
                result.append(contentsOf: extractImages(from: paragraph))
            }
        }

        return result
    }

    private func parseCode(lines: [String], index: inout Int) -> Block {
        let opener = lines[index].trimmingCharacters(in: .whitespaces)
        let fence = String(opener.prefix { $0 == "`" || $0 == "~" })
        let language = opener.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        index += 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }

        return .code(language: language, content: codeLines.joined(separator: "\n"))
    }

    private func parseTable(lines: [String], index: inout Int) -> Block {
        let headers = splitTableRow(lines[index])
        var rows: [[String]] = []
        index += 2

        while index < lines.count {
            let row = splitTableRow(lines[index])
            guard row.count >= 2, !isTableSeparator(lines[index]) else { break }
            rows.append(row)
            index += 1
        }

        return .table(headers: headers, rows: rows)
    }

    private func parseList(lines: [String], index: inout Int) -> Block {
        var items: [ListItem] = []
        let ordered = orderedListText(lines[index]) != nil

        while index < lines.count {
            let line = lines[index]
            guard let parsed = parseListItem(line) else { break }
            if ordered != (orderedListText(line) != nil) && parsed.depth == 0 { break }
            items.append(parsed)
            index += 1
        }

        return .list(items: items, ordered: ordered)
    }

    private func parseBlockquote(lines: [String], index: inout Int) -> Block {
        var quoteLines: [String] = []
        while index < lines.count, isBlockquoteLine(lines[index]) {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            line.removeFirst()
            quoteLines.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return .blockquote(quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseParagraph(lines: [String], index: inout Int) -> String {
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                break
            }
            if isFence(trimmed) || parseHeading(trimmed) != nil || isHorizontalRule(trimmed) ||
                isTableStart(at: index, in: lines) || isListLine(line) || isBlockquoteLine(line) {
                break
            }
            paragraphLines.append(line)
            index += 1
        }

        if paragraphLines.isEmpty {
            paragraphLines.append(lines[index])
            index += 1
        }

        return paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImages(from text: String) -> [Block] {
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
            }

            remaining = remaining[match.range.upperBound...]
        }

        let after = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !after.isEmpty {
            blocks.append(.paragraph(after))
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } ||
            stripped.allSatisfy { $0 == "*" } ||
            stripped.allSatisfy { $0 == "_" }
    }

    private func isBlockquoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private func isListLine(_ line: String) -> Bool {
        parseListItem(line) != nil
    }

    private func parseListItem(_ line: String) -> ListItem? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { total, char in
            total + (char == "\t" ? 4 : 1)
        }
        let depth = indent / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return listItem(text: String(trimmed.dropFirst(2)), depth: depth)
        }
        if let text = orderedListText(line) {
            return listItem(text: text, depth: depth)
        }
        return nil
    }

    private func orderedListText(_ line: String) -> String? {
        guard let match = line.trimmingCharacters(in: .whitespaces).wholeMatch(of: /^\d+[\.)]\s+(.*)/) else {
            return nil
        }
        return String(match.1)
    }

    private func listItem(text: String, depth: Int) -> ListItem {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[ ] ") {
            return ListItem(text: String(trimmed.dropFirst(4)), depth: depth, checked: false)
        }
        if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return ListItem(text: String(trimmed.dropFirst(4)), depth: depth, checked: true)
        }
        return ListItem(text: text, depth: depth, checked: nil)
    }

    private func isTableStart(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let headers = splitTableRow(lines[index])
        guard headers.count >= 2 else { return false }
        return isTableSeparator(lines[index + 1])
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
                .replacingOccurrences(of: " ", with: "")
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            renderInline(text)
                .textSelection(.enabled)

        case .heading(let level, let text):
            renderInline(stripImageSyntax(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 4 : 2)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(item, index: index, ordered: ordered)
                }
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(WeeTheme.accent.opacity(0.65))
                    .frame(width: 3)
                renderInline(text)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .code(let language, let content):
            codeView(language: language, content: content)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .image(let alt, let url):
            imageView(alt: alt, url: url)

        case .horizontalRule:
            Rectangle()
                .fill(WeeTheme.glassStroke)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        case 3: return .subheadline.bold()
        default: return .body.bold()
        }
    }

    private func listRow(_ item: ListItem, index: Int, ordered: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(listMarker(item, index: index, ordered: ordered))
                .font(.body)
                .foregroundStyle(WeeTheme.textMuted)
                .frame(width: item.checked == nil && !ordered ? 10 : 24, alignment: .trailing)
            renderInline(stripImageSyntax(item.text))
                .textSelection(.enabled)
        }
        .padding(.leading, CGFloat(item.depth * 18))
    }

    private func listMarker(_ item: ListItem, index: Int, ordered: Bool) -> String {
        if let checked = item.checked {
            return checked ? "[x]" : "[ ]"
        }
        return ordered ? "\(index + 1)." : "•"
    }

    private func codeView(language: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
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
                    .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
                    .padding(8)
                    .background(isHeader ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(Rectangle().stroke(WeeTheme.glassStroke.opacity(0.7)))
            }
        }
    }

    @ViewBuilder
    private func imageView(alt: String, url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, maxHeight: 320)
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
                    Text(alt.isEmpty ? "Loading image..." : alt)
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textMuted)
                }
                .padding(8)
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
