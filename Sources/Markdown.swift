import AppKit

/// A small, fast Markdown renderer tuned for chat answers.
/// Supports fenced code, headings, lists, quotes, rules, and inline bold / italic / code / links.
enum Markdown {
    static func render(_ text: String, baseSize: CGFloat = 13.5, color: NSColor = .labelColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: baseSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)

        let normal: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph(spacing: 5, lineSpacing: 4),
        ]

        let lines = text.components(separatedBy: "\n")
        var index = 0
        var inCode = false
        var codeBuffer: [String] = []

        func flushCode() {
            guard !codeBuffer.isEmpty else { return }
            let code = codeBuffer.joined(separator: "\n")
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 8
            style.firstLineHeadIndent = 10
            style.headIndent = 10
            out.append(NSAttributedString(string: code + "\n", attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.5),
                .paragraphStyle: style,
            ]))
            codeBuffer.removeAll()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode { flushCode(); inCode = false } else { inCode = true }
                index += 1
                continue
            }
            if inCode {
                codeBuffer.append(raw)
                index += 1
                continue
            }

            if line.isEmpty {
                out.append(NSAttributedString(string: "\n", attributes: normal))
                index += 1
                continue
            }

            if line == "---" || line == "***" || line == "___" {
                let hr = NSMutableParagraphStyle()
                hr.paragraphSpacing = 8
                out.append(NSAttributedString(string: "────────────\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: hr,
                ]))
                index += 1
                continue
            }

            if let heading = headingLevel(line) {
                let size: CGFloat = heading.level == 1 ? baseSize + 3 : (heading.level == 2 ? baseSize + 1.5 : baseSize + 0.5)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph(spacing: 4, lineSpacing: 3, before: heading.level == 1 ? 8 : 6),
                ]
                out.append(inline(heading.text, baseSize: size, attrs: attrs))
                out.append(NSAttributedString(string: "\n", attributes: normal))
                index += 1
                continue
            }

            if let bullet = bulletText(line) {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                style.paragraphSpacing = 3
                style.firstLineHeadIndent = 6
                style.headIndent = 17
                style.tabStops = [NSTextTab(textAlignment: .left, location: 17)]
                let marker = bullet.ordered ? "\(bullet.marker)\t" : "•\t"
                out.append(NSAttributedString(string: marker, attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: style,
                ]))
                var attrs = normal
                attrs[.paragraphStyle] = style
                out.append(inline(bullet.text, baseSize: baseSize, attrs: attrs))
                out.append(NSAttributedString(string: "\n", attributes: normal))
                index += 1
                continue
            }

            if line.hasPrefix("> ") {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                style.paragraphSpacing = 4
                style.firstLineHeadIndent = 10
                style.headIndent = 10
                out.append(NSAttributedString(string: "▎", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: style,
                ]))
                out.append(inline(String(line.dropFirst(2)), baseSize: baseSize, attrs: [
                    .font: baseFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ]))
                out.append(NSAttributedString(string: "\n", attributes: normal))
                index += 1
                continue
            }

            out.append(inline(raw, baseSize: baseSize, attrs: normal))
            out.append(NSAttributedString(string: "\n", attributes: normal))
            index += 1
        }
        flushCode()
        return out
    }

    // MARK: - Inline

    private static let inlineRegex = try! NSRegularExpression(
        pattern: "`([^`]+)`|\\*\\*([^*]+)\\*\\*|__([^_]+)__|\\*([^*\\n]+)\\*|\\[([^\\]]+)\\]\\(([^)]+)\\)",
        options: []
    )

    private static func inline(_ text: String, baseSize: CGFloat, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = text as NSString
        var cursor = 0
        let matches = inlineRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            if match.range.location > cursor {
                result.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), attributes: attrs))
            }
            if let range = Range(match.range(at: 1), in: text) {
                var codeAttrs = attrs
                codeAttrs[.font] = NSFont.monospacedSystemFont(ofSize: baseSize - 0.8, weight: .regular)
                codeAttrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.6)
                result.append(NSAttributedString(string: String(text[range]), attributes: codeAttrs))
            } else if let range = Range(match.range(at: 2), in: text) ?? Range(match.range(at: 3), in: text) {
                var bold = attrs
                let size = (attrs[.font] as? NSFont)?.pointSize ?? baseSize
                bold[.font] = NSFont.systemFont(ofSize: size, weight: .semibold)
                result.append(NSAttributedString(string: String(text[range]), attributes: bold))
            } else if let range = Range(match.range(at: 4), in: text) {
                var italic = attrs
                italic[.obliqueness] = 0.18
                result.append(NSAttributedString(string: String(text[range]), attributes: italic))
            } else if let label = Range(match.range(at: 5), in: text), let target = Range(match.range(at: 6), in: text) {
                var link = attrs
                link[.link] = String(text[target])
                link[.foregroundColor] = NSColor.linkColor
                result.append(NSAttributedString(string: String(text[label]), attributes: link))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: attrs))
        }
        return result
    }

    // MARK: - Blocks

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return (level, String(line.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func bulletText(_ line: String) -> (ordered: Bool, marker: String, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return (false, "", String(line.dropFirst(2)))
        }
        if let match = line.range(of: "^\\d{1,2}[.)] ", options: .regularExpression) {
            let marker = String(line[match]).trimmingCharacters(in: .whitespaces)
            return (true, marker, String(line[match.upperBound...]))
        }
        return nil
    }

    private static func paragraph(spacing: CGFloat, lineSpacing: CGFloat, before: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = before
        return style
    }
}
