import Foundation

/// Renders translated pages as a LaTeX document.
///
/// The model is asked to emit Markdown with `$...$` / `$$...$$` math. Prose is escaped,
/// math is passed through (after a safety pass), so formulas are typeset instead of
/// showing up as the glyph soup that PDF text extraction produces.
enum TranslationTeX {
    // MARK: - Document

    static func document(doc: PaperDoc, pages: [Int: String], language: String) -> String {
        let layout = PaperLayout.inspect(doc.url)
        var source = #"""
        \documentclass[11pt,a4paper]{article}
        \usepackage{fontspec}
        \usepackage{xeCJK}
        \setmainfont{Times New Roman}
        \setCJKmainfont{PingFang SC}
        \usepackage{amsmath,amssymb,mathtools}
        \usepackage[margin=22mm,headheight=16pt]{geometry}
        \usepackage{xcolor}
        \usepackage{fancyhdr}
        \usepackage{hyperref}
        \usepackage{enumitem}
        \usepackage{booktabs}
        \usepackage{array}
        \definecolor{ink}{HTML}{565F9C}
        \hypersetup{colorlinks=true,linkcolor=ink,urlcolor=ink}
        \pagestyle{fancy}\fancyhf{}
        \renewcommand{\headrulewidth}{0pt}
        \fancyfoot[C]{\small\thepage}
        \setlength{\parindent}{0pt}
        \setlength{\parskip}{6pt}
        \linespread{1.25}
        \emergencystretch=4em
        \allowdisplaybreaks
        \begin{document}
        """#

        let sample = String(pages.values.joined().prefix(4000))
        if sample.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            source = source.replacingOccurrences(of: "PingFang SC", with: "Apple SD Gothic Neo")
        }
        if sample.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
            source = source.replacingOccurrences(of: "Times New Roman", with: "Arial Unicode MS")
            source = source.replacingOccurrences(of: "\\begin{document}", with: "\\usepackage{bidi}\n\\begin{document}")
        }

        let dimensions = String(format: "paperwidth=%.2fbp,paperheight=%.2fbp,left=%.2fbp,right=%.2fbp,top=%.2fbp,bottom=%.2fbp,headheight=16pt", Double(layout.width), Double(layout.height), Double(layout.left), Double(layout.right), Double(layout.top), Double(layout.bottom))
        source = source.replacingOccurrences(of: "margin=22mm,headheight=16pt", with: dimensions)
        let point = layout.fontSize <= 10 ? "10pt" : (layout.fontSize >= 12 ? "12pt" : "11pt")
        // Class option, not multicols: starred floats can then span both columns.
        let options = layout.columns == 2 ? point + ",twocolumn" : point
        source = source.replacingOccurrences(of: "[11pt,a4paper]", with: "[\(options)]")
        if layout.serif { source = source.replacingOccurrences(of: "PingFang SC", with: "Songti SC") }
        if layout.columns == 2 {
            source = source.replacingOccurrences(of: "\\begin{document}", with: "\\setlength{\\columnsep}{18pt}\n\\begin{document}")
        }
        let spanningFloats = layout.columns == 2
        for key in pages.keys.sorted() {
            // Invisible PDF bookmarks retain provenance without inserting page headings.
            source += "\\pdfbookmark[1]{pc-source-\(key)}{pc-source-\(key)}\n"
            let content = pages[key] ?? ""
            let rendered = body(content, spanningFloats: spanningFloats)
            if content.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
                source += "\\begin{RTL}\n" + rendered + "\\end{RTL}\n"
            } else { source += rendered }
        }
        source += "\\end{document}\n"
        return source
    }

    // MARK: - Prose

    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\textbackslash{}"
            case "{": out += "\\{"
            case "}": out += "\\}"
            case "$": out += "\\$"
            case "&": out += "\\&"
            case "#": out += "\\#"
            case "%": out += "\\%"
            case "_": out += "\\_"
            case "~": out += "\\textasciitilde{}"
            case "^": out += "\\textasciicircum{}"
            default: out.append(character)
            }
        }
        return out
    }

    /// Markdown + math to LaTeX body.
    /// `spanningFloats` places wide tables and figure notes across both columns.
    static func body(_ markdown: String, spanningFloats: Bool = false) -> String {
        var output = ""
        var paragraph: [String] = []
        var displayMath: [String] = []
        var inDisplay = false
        var listKind: String?
        var quoteDepth = 0
        var tableBuffer: [String] = []

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.map { inline($0) }.joined(separator: " ")
            output += joined + "\n\n"
            paragraph.removeAll()
        }

        func closeList() {
            if let kind = listKind {
                output += "\\end{\(kind)}\n"
                listKind = nil
            }
        }

        func closeQuote() {
            while quoteDepth > 0 {
                output += "\\end{quote}\n"
                quoteDepth -= 1
            }
        }

        func flushTable() {
            guard !tableBuffer.isEmpty else { return }
            if let rendered = table(tableBuffer, spanning: spanningFloats) {
                closeParagraph()
                closeList()
                closeQuote()
                output += rendered + "\n"
            } else {
                paragraph.append(contentsOf: tableBuffer)
            }
            tableBuffer.removeAll()
        }

        func flush() {
            flushTable()
            closeParagraph()
            closeList()
            closeQuote()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Display math blocks
            if inDisplay {
                if let range = line.range(of: "$$") ?? line.range(of: "\\]") {
                    let before = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty { displayMath.append(before) }
                    output += renderDisplay(displayMath)
                    displayMath.removeAll()
                    inDisplay = false
                    let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !after.isEmpty { paragraph.append(after) }
                } else {
                    displayMath.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("$$") {
                flush()
                let rest = String(line.dropFirst(2))
                if let end = rest.range(of: "$$") {
                    let inner = String(rest[..<end.lowerBound])
                    output += renderDisplay(inner.components(separatedBy: .newlines))
                } else {
                    inDisplay = true
                    displayMath = rest.isEmpty ? [] : [rest]
                }
                continue
            }
            if line.hasPrefix("\\[") {
                flush()
                let rest = String(line.dropFirst(2))
                if let end = rest.range(of: "\\]") {
                    output += renderDisplay(String(rest[..<end.lowerBound]).components(separatedBy: .newlines))
                } else {
                    inDisplay = true
                    displayMath = rest.isEmpty ? [] : [rest]
                }
                continue
            }

            if line.hasPrefix("|") {
                tableBuffer.append(line)
                continue
            }
            if !tableBuffer.isEmpty { flushTable() }

            if line.isEmpty {
                flush()
                continue
            }

            if let caption = figureCaption(line) {
                flush()
                output += figureNote(caption, spanning: spanningFloats)
                continue
            }

            if line.hasPrefix("#") {
                flush()
                let heading = line.drop(while: { $0 == "#" || $0 == " " })
                let depth = line.prefix(while: { $0 == "#" }).count
                let command = depth == 1 ? "section" : (depth == 2 ? "subsection" : "subsubsection")
                output += "\\" + command + "*{" + inline(String(heading)) + "}\n"
                continue
            }

            if line.hasPrefix(">") {
                closeParagraph()
                closeList()
                let text = line.drop(while: { $0 == ">" }).trimmingCharacters(in: .whitespaces)
                if quoteDepth == 0 { output += "\\begin{quote}\n"; quoteDepth = 1 }
                output += inline(text) + "\n\n"
                continue
            }
            closeQuote()

            if isBullet(line) {
                closeParagraph()
                if listKind != "itemize" {
                    closeList()
                    output += "\\begin{itemize}[leftmargin=1.6em,itemsep=2pt]\n"
                    listKind = "itemize"
                }
                output += "\\item " + inline(String(line.dropFirst(2))) + "\n"
                continue
            }
            if let ordered = orderedItem(line) {
                closeParagraph()
                if listKind != "enumerate" {
                    closeList()
                    output += "\\begin{enumerate}[leftmargin=1.8em,itemsep=2pt]\n"
                    listKind = "enumerate"
                }
                output += "\\item " + inline(ordered) + "\n"
                continue
            }

            closeList()

            paragraph.append(rawLine)
        }

        if inDisplay, !displayMath.isEmpty { output += renderDisplay(displayMath) }
        flush()
        return output
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let range = line.range(of: "^\\d{1,2}[.)]\\s+", options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }

    // MARK: - Figures

    /// A whole line `![图注](figure)` is a caption, not a placed image.
    static func figureCaption(_ line: String) -> String? {
        guard line.hasPrefix("![") else { return nil }
        guard let bracket = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let target = String(line[bracket.upperBound...].dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
        guard target.isEmpty || target == "figure" || target == "fig" || target == "image" else { return nil }
        return String(line[line.index(line.startIndex, offsetBy: 2)..<bracket.lowerBound])
    }

    private static func figureNote(_ caption: String, spanning: Bool) -> String {
        let env = spanning ? "figure*" : "figure"
        let label = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let rendered = label.isEmpty ? "图注缺失" : inline(label)
        return """
        \\begin{\(env)}[ht]
        \\centering
        \\fbox{\\parbox{0.92\\linewidth}{\\centering\\small 原文插图保留在源 PDF。译文只保留图注，不按坐标重排。\\par\\vspace{3pt}\(rendered)}}
        \\end{\(env)}

        """
    }

    // MARK: - Tables

    /// Parses a Markdown table. Wide tables span the page when the document is two-column.
    /// Cells wrap. The grid is never scaled down with \\resizebox.
    static func table(_ lines: [String], spanning: Bool = false) -> String? {
        let rows = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        guard rows.count >= 2 else { return nil }
        let cells = rows.map { row -> [String] in
            var text = row.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("|") { text.removeFirst() }
            if text.hasSuffix("|") { text.removeLast() }
            return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard let header = cells.first else { return nil }
        let bodyRows = cells.dropFirst().filter { row in
            !row.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } }
        }
        guard !bodyRows.isEmpty else { return nil }
        let columns = max(header.count, bodyRows.map(\.count).max() ?? header.count)

        func rowTeX(_ cells: [String]) -> String {
            var padded = cells
            while padded.count < columns { padded.append("") }
            return padded.prefix(columns).map { inline($0) }.joined(separator: " & ") + " \\\\"
        }

        let longest = ([header] + bodyRows).flatMap { $0 }.map(\.count).max() ?? 0
        let wide = columns >= 4 || longest > 42
        let useSpan = spanning && wide
        let measure = useSpan ? "\\textwidth" : "\\linewidth"
        let width = "\\dimexpr(\(measure)-" + String(columns * 2) + "\\tabcolsep)/" + String(max(1, columns)) + "\\relax"
        let spec = String(repeating: ">{\\raggedright\\arraybackslash}p{\(width)}", count: columns)
        var grid = "\\begin{tabular}{" + spec + "}\n"
        grid += "\\toprule\n" + rowTeX(header) + "\n\\midrule\n"
        for row in bodyRows { grid += rowTeX(row) + "\n" }
        grid += "\\bottomrule\n\\end{tabular}\n"
        if useSpan {
            return "\\begin{table*}[ht]\\centering\\small\\setlength{\\tabcolsep}{4pt}\n" + grid + "\\end{table*}\n"
        }
        return "\\begin{center}\\small\\setlength{\\tabcolsep}{4pt}\n" + grid + "\\end{center}\n"
    }

    // MARK: - Math

    private static func renderDisplay(_ lines: [String]) -> String {
        let raw = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if let math = sanitizeMath(raw) {
            return "\\[\n" + math + "\n\\]\n\n"
        }
        return escape(raw) + "\n\n"
    }

    /// Converts a math snippet to something XeLaTeX can typeset, or nil when unsafe.
    static func sanitizeMath(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$") && text.hasSuffix("$") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        guard !text.isEmpty else { return nil }
        if text.contains("$") { return nil }
        // Chinese is allowed inside \text{...}; outside it, math must stay symbolic.
        var outsideText = text
        while let start = outsideText.range(of: "\\text{") {
            var depth = 1
            var index = start.upperBound
            var end = outsideText.endIndex
            while index < outsideText.endIndex {
                let character = outsideText[index]
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { end = outsideText.index(after: index); break }
                }
                index = outsideText.index(after: index)
            }
            outsideText.removeSubrange(start.lowerBound..<end)
        }
        if outsideText.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return nil }

        var balance = 0
        for character in text {
            if character == "{" { balance += 1 }
            if character == "}" { balance -= 1 }
            if balance < 0 { return nil }
        }
        if balance != 0 { return nil }

        text = unicodeToLaTeX(text)
        return text
    }

    private static let symbolMap: [String: String] = [
        "≤": "\\le ", "≥": "\\ge ", "≠": "\\ne ", "≈": "\\approx ", "≡": "\\equiv ",
        "∈": "\\in ", "∉": "\\notin ", "⊂": "\\subset ", "⊆": "\\subseteq ", "⊃": "\\supset ",
        "∪": "\\cup ", "∩": "\\cap ", "∅": "\\emptyset ", "∀": "\\forall ", "∃": "\\exists ",
        "→": "\\to ", "←": "\\leftarrow ", "⇒": "\\Rightarrow ", "⇔": "\\Leftrightarrow ",
        "∞": "\\infty ", "∂": "\\partial ", "∇": "\\nabla ", "√": "\\sqrt ", "∑": "\\sum ",
        "∏": "\\prod ", "∫": "\\int ", "±": "\\pm ", "×": "\\times ", "÷": "\\div ", "·": "\\cdot ",
        "∝": "\\propto ", "∼": "\\sim ", "≪": "\\ll ", "≫": "\\gg ", "…": "\\ldots ",
        "α": "\\alpha ", "β": "\\beta ", "γ": "\\gamma ", "δ": "\\delta ", "ε": "\\epsilon ",
        "ϵ": "\\epsilon ", "ζ": "\\zeta ", "η": "\\eta ", "θ": "\\theta ", "ϑ": "\\vartheta ",
        "ι": "\\iota ", "κ": "\\kappa ", "λ": "\\lambda ", "μ": "\\mu ", "ν": "\\nu ", "ξ": "\\xi ",
        "π": "\\pi ", "ρ": "\\rho ", "σ": "\\sigma ", "τ": "\\tau ", "υ": "\\upsilon ", "φ": "\\phi ",
        "ϕ": "\\phi ", "χ": "\\chi ", "ψ": "\\psi ", "ω": "\\omega ",
        "Γ": "\\Gamma ", "Δ": "\\Delta ", "Θ": "\\Theta ", "Λ": "\\Lambda ", "Ξ": "\\Xi ",
        "Π": "\\Pi ", "Σ": "\\Sigma ", "Φ": "\\Phi ", "Ψ": "\\Psi ", "Ω": "\\Omega ",
        "′": "'", "″": "''", "−": "-", "–": "-", "—": "-",
    ]

    private static func unicodeToLaTeX(_ text: String) -> String {
        var out = ""
        for character in text {
            if let mapped = symbolMap[String(character)] {
                out += mapped
            } else {
                out.append(character)
            }
        }
        return out
    }

    // MARK: - Inline markdown

    static func inline(_ raw: String) -> String {
        var out = ""
        let chars = Array(raw)
        var index = 0

        func findClosing(_ marker: [Character], from start: Int) -> Int? {
            var i = start
            while i + marker.count <= chars.count {
                if Array(chars[i..<(i + marker.count)]) == marker { return i }
                i += 1
            }
            return nil
        }

        while index < chars.count {
            let character = chars[index]

            if character == "\\", index + 1 < chars.count, chars[index + 1] == "(" || chars[index + 1] == "[" {
                let closing: [Character] = chars[index + 1] == "(" ? ["\\", ")"] : ["\\", "]"]
                if let close = findClosing(closing, from: index + 2) {
                    let mathText = String(chars[(index + 2)..<close])
                    if let math = sanitizeMath(mathText) {
                        out += "$" + math + "$"
                        index = close + 2
                        continue
                    }
                }
            }

            if character == "$" {
                var start = index + 1
                if start < chars.count, chars[start] == "$" { start += 1 }
                if let close = findClosing(["$"], from: start) {
                    let mathText = String(chars[start..<close])
                    if let math = sanitizeMath(mathText) {
                        out += "$" + math + "$"
                        index = close + 1
                        continue
                    }
                }
                out += "\\$"
                index += 1
                continue
            }

            if character == "`", let close = findClosing(["`"], from: index + 1) {
                out += "\\texttt{" + escape(String(chars[(index + 1)..<close])) + "}"
                index = close + 1
                continue
            }

            if character == "*", index + 1 < chars.count, chars[index + 1] == "*",
               let close = findClosing(["*", "*"], from: index + 2) {
                out += "\\textbf{" + inline(String(chars[(index + 2)..<close])) + "}"
                index = close + 2
                continue
            }

            if character == "[",
               let closeBracket = findClosing(["]"], from: index + 1),
               closeBracket + 1 < chars.count, chars[closeBracket + 1] == "(",
               let closeParen = findClosing([")"], from: closeBracket + 2) {
                let label = String(chars[(index + 1)..<closeBracket])
                let target = String(chars[(closeBracket + 2)..<closeParen])
                out += "\\href{" + escape(target) + "}{" + inline(label) + "}"
                index = closeParen + 1
                continue
            }

            out += escape(String(character))
            index += 1
        }
        return out
    }
}
