import AppKit

/// Model prose is escaped as text; only this trusted template supplies TeX commands.
enum LearningReport {
    static func escape(_ text: String) -> String {
        let replacements: [Character: String] = ["\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "$": "\\$", "&": "\\&", "#": "\\#", "%": "\\%", "_": "\\_", "~": "\\textasciitilde{}", "^": "\\textasciicircum{}"]
        return text.map { replacements[$0] ?? String($0) }.joined()
    }

    static func body(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" || $0 == " " })
                return "\\section*{" + escape(String(heading)) + "}"
            }
            let cleaned = line.replacingOccurrences(of: "**", with: "")
            return escape(cleaned) + "\n\n"
        }.joined(separator: "\n")
    }

    static func source(state: DocState, summary: String) -> String {
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        var output = #"""
        \documentclass[11pt,a4paper]{article}
        \usepackage{fontspec}
        \usepackage{xeCJK}
        \setmainfont{Times New Roman}
        \setCJKmainfont{PingFang SC}
        \usepackage[margin=25mm,headheight=16pt]{geometry}
        \usepackage{xcolor}
        \usepackage{fancyhdr}
        \usepackage{hyperref}
        \definecolor{ink}{HTML}{565F9C}
        \hypersetup{colorlinks=true,linkcolor=ink,urlcolor=ink}
        \pagestyle{fancy}\fancyhf{}
        \fancyhead[L]{\small\color{ink}论文伴侣 · 学习报告}
        \fancyfoot[C]{\small\thepage}
        \setlength{\parindent}{0pt}
        \setlength{\parskip}{7pt}
        \linespread{1.25}
        \emergencystretch=3em
        \begin{document}
        \begin{titlepage}
        \vspace*{25mm}
        {\color{ink}\Large PAPER COMPANION}\par
        \vspace{12mm}
        {\Huge\bfseries 阅读与理解}\par
        \vspace{6mm}
        {\Large 学习报告}\par
        \vspace{12mm}
        \hrule
        \vspace{8mm}
        """#
        output += "{\\Large " + escape(state.doc.title) + "}\\par\n\\vspace{10mm}\n"
        output += escape("阅读起点：" + (state.readingLevel ?? .beginner).title) + "\\par\n"
        output += escape("交流 \(state.threads.count) 次 · 标注 \(state.highlights.count) 处 · \(date)") + "\\par\n"
        output += "\\vfill\n本报告根据阅读交流整理。AI 回答与总结需结合原文核实，不能代替原文证据。\n\\end{titlepage}\n"
        output += body(summary)
        output += "\\clearpage\n\\section*{附录：完整阅读交流}\n"
        for (index, thread) in state.threads.enumerated() {
            output += "\\subsection*{" + escape("\(index + 1). 第 \(thread.page + 1) 页") + "}\n"
            if let quote = thread.quote, !quote.isEmpty { output += "\\textbf{选中原文}\\par\n" + body(quote) }
            output += "\\textbf{提问}\\par\n" + body(thread.question)
            output += "\\textbf{交流回答（待原文核实）}\\par\n" + body(thread.answer)
        }
        output += "\\end{document}\n"
        return output
    }

    static func export(state: DocState, summary: String, to url: URL) -> (pdf: URL?, message: String) {
        return exportSource(source(state: state, summary: summary), to: url)
    }

    static func exportSource(_ source: String, to url: URL) -> (pdf: URL?, message: String) {
        do { try source.write(to: url, atomically: true, encoding: .utf8) }
        catch { return (nil, "导出失败：" + error.localizedDescription) }
        let engines = ["/Library/TeX/texbin/xelatex", "/opt/homebrew/bin/xelatex", "/usr/local/bin/xelatex"]
        guard let engine = engines.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return (nil, "已保存可编辑的 .tex 源码。生成 PDF 需要安装包含 XeLaTeX 的 MacTeX。")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let input = work.appendingPathComponent("report.tex")
            try FileManager.default.copyItem(at: url, to: input)
            let logURL = work.appendingPathComponent("compile.txt")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            for _ in 0..<2 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: engine)
            process.currentDirectoryURL = work
            process.arguments = ["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error", "report.tex"]
            process.standardOutput = log
            process.standardError = log
            try process.run()
            let deadline = Date().addingTimeInterval(60)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.8)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                return (nil, "源码已保存，PDF 编译超时。可使用 XeLaTeX 手动编译。")
            }
            guard process.terminationStatus == 0 else {
                let destination = url.deletingPathExtension().appendingPathExtension("log")
                try Data(contentsOf: logURL).write(to: destination, options: .atomic)
                return (nil, "源码已保存，PDF 编译失败；请查看同名 .log 文件。")
            }
            }
            let pdf = url.deletingPathExtension().appendingPathExtension("pdf")
            // Avoid overwriting a sibling PDF the save panel did not approve.
            let destination = FileManager.default.fileExists(atPath: pdf.path)
                ? url.deletingPathExtension().appendingPathExtension("\(UUID().uuidString.prefix(8)).pdf") : pdf
            try Data(contentsOf: work.appendingPathComponent("report.pdf")).write(to: destination, options: .atomic)
            return (destination, "已生成 PDF 和可编辑的 LaTeX 源码，包含学习总结及完整问答附录。")
        } catch { return (nil, "源码已保存，PDF 导出失败：" + error.localizedDescription) }
    }
}
