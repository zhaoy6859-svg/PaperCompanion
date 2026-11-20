import Foundation
import CoreGraphics

@main struct LayoutPolicyTests {
    static func main() {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let wideLines = (0..<20).map { CGRect(x: 40, y: CGFloat($0) * 14, width: 520, height: 10) }
        assert(!PaperLayout.looksTwoColumn(lineBounds: wideLines, page: page))
        var columnLines: [CGRect] = []
        for index in 0..<18 {
            columnLines.append(CGRect(x: 36, y: CGFloat(index) * 14, width: 240, height: 10))
            columnLines.append(CGRect(x: 320, y: CGFloat(index) * 14, width: 240, height: 10))
        }
        assert(PaperLayout.looksTwoColumn(lineBounds: columnLines, page: page))

        let wide = TranslationTeX.table(["| a | b | c | d | e |", "| --- | --- | --- | --- | --- |", "| 很长的单元格内容需要换行而不是缩小到看不清 | 2 | 3 | 4 | 5 |"], spanning: true)
        assert(wide?.contains("table*") == true)
        assert(wide?.contains("resizebox") != true)
        assert(wide?.contains("p{") == true)
        let narrow = TranslationTeX.table(["| 参数 | 含义 |", "| --- | --- |", "| n | 数量 |"], spanning: true)
        assert(narrow?.contains("table*") != true)
        assert(narrow?.contains("resizebox") != true)

        let figure = TranslationTeX.body("![土壤侵蚀示意图](figure)\n\n正文。", spanningFloats: true)
        assert(figure.contains("\\begin{figure*}"))
        assert(figure.contains("土壤侵蚀示意图"))
        assert(!figure.contains("\\resizebox"))
        let single = TranslationTeX.body("![图](figure)", spanningFloats: false)
        assert(single.contains("\\begin{figure}"))
        assert(!single.contains("figure*"))
        print("PASS: column vote, wrapping tables, figure notes")
    }
}
