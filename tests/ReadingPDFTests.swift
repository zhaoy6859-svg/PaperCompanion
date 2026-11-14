import Foundation
import PDFKit
@main struct ReadingPDFTests {
    static func main() throws {
        let fixture = #"\documentclass{article}\usepackage[paperwidth=612pt,paperheight=792pt,margin=50pt]{geometry}\begin{document}Source page one.\newpage Source page two.\end{document}"#
        let fixtureResult = LearningReport.exportSource(fixture, to: URL(fileURLWithPath: "/tmp/pc-source-fixture.tex"))
        guard let fixturePDF = fixtureResult.pdf else { fatalError(fixtureResult.message) }
        try Data(contentsOf: fixturePDF).write(to: URL(fileURLWithPath: "/tmp/pc-v4-source.pdf"))
        let doc = PaperDoc(path: "/tmp/pc-v4-source.pdf", title: "统计学习：目标函数与参数估计", pages: [PaperPage(index: 0, text: "Research"), PaperPage(index: 1, text: "Evidence")], language: .english, needsOCR: false, truncated: false, fullText: "Research", charCount: 8, captions: [:])
        let math = #"""
        ## 参数估计
        参数 $\theta$ 通过最小化期望损失确定。这里的 $\ell_\theta(X,Y)$ 表示给定参数下的预测误差。
        $$
        \hat{\theta}=\operatorname*{arg\,min}_{\theta\in\Theta}\mathbb{E}\left[\ell_\theta(X,Y)\right]\tag{1}
        $$
        ## 有限样本近似
        用 $n$ 个观测值的平均损失近似总体期望：
        $$
        \widehat{R}_n(\theta)=\frac{1}{n}\sum_{i=1}^{n}\left(y_i-f_\theta(x_i)\right)^2.\tag{2}
        $$
        所有符号应与原文逐项核对；估计目标与算法求解步骤需要区分。
        """#
        let source = TranslationTeX.document(doc: doc, pages: [0: math, 1: "## 证据与局限\n结果依赖于样本代表性与模型假设。"], language: "简体中文")
        assert(!source.contains("原文第"))
        assert(!source.contains("\\clearpage"))
        assert(source.contains("\\subsection*{参数估计}"))
        assert(source.contains(String(format: "paperwidth=%.2fbp", Double(PaperLayout.inspect(doc.url).width))))
        assert(source.contains("\\frac{1}{n}"))
        assert(source.contains("\\operatorname*{arg\\,min}"))
        let result = LearningReport.exportSource(source, to: URL(fileURLWithPath: "/tmp/pc-v4-math.tex"))
        guard let pdf = result.pdf else { fatalError(result.message) }
        print("PASS: mathematical LaTeX PDF \(pdf.path)")
        let output = PDFDocument(url: pdf)!
        assert(abs(output.page(at: 0)!.bounds(for: .cropBox).width - PaperLayout.inspect(doc.url).width) < 0.1)
        assert(output.pageCount == 1, "Translation should flow continuously")
        assert(output.outlineRoot?.numberOfChildren == 2, "Invisible source anchors must survive compilation")
        let columnFixture = #"\documentclass[twocolumn]{article}\begin{document}"# + String(repeating: "Column layout evidence with several words on each line. ", count: 300) + #"\end{document}"#
        let columnResult = LearningReport.exportSource(columnFixture, to: URL(fileURLWithPath: "/tmp/pc-columns.tex"))
        guard let columnPDF = columnResult.pdf else { fatalError(columnResult.message) }
        assert(PaperLayout.inspect(columnPDF).columns == 2)
        var columnDoc = doc
        columnDoc.path = columnPDF.path
        let columnSource = TranslationTeX.document(doc: columnDoc, pages: [0: "# 研究方法\n\n| 参数 | 含义 |\n| --- | --- |\n| $n$ | 数量 |\n\n正文与公式 $x^2$。"], language: "简体中文")
        assert(columnSource.contains("\\begin{multicols}{2}"))
        let columnTranslation = LearningReport.exportSource(columnSource, to: URL(fileURLWithPath: "/tmp/pc-column-translation.tex"))
        guard columnTranslation.pdf != nil else { fatalError(columnTranslation.message) }
        print("PASS: continuous flow, source bookmarks, source dimensions, two columns and table compilation")
        let pages: [Int: String] = [0: math, 1: "## 证据与局限\n结果依赖于样本代表性与模型假设。"]
        try JSONEncoder().encode(pages).write(to: URL(fileURLWithPath: "/tmp/pc-v4-translations.json"))
    }
}
