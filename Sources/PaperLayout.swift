import AppKit
import PDFKit

/// Reuses measurable source geometry; text reflows because translation lengths differ.
struct PaperLayout {
    var width: CGFloat = 595.28
    var height: CGFloat = 841.89
    var left: CGFloat = 56
    var right: CGFloat = 56
    var top: CGFloat = 56
    var bottom: CGFloat = 56
    var columns = 1
    var fontSize: CGFloat = 11
    var serif = true

    static func inspect(_ url: URL) -> PaperLayout {
        var result = PaperLayout()
        guard let pdf = PDFDocument(url: url), let first = pdf.page(at: 0) else { return result }
        let paper = first.bounds(for: .cropBox)
        if paper.width > 200, paper.height > 200 { result.width = paper.width; result.height = paper.height }
        var columnVotes = 0
        var analyzed = 0
        var fontCounts: [Int: Int] = [:]
        var serifCount = 0, sansCount = 0
        var bounds: [CGRect] = []
        for index in 0..<min(5, pdf.pageCount) {
            guard let page = pdf.page(at: index), let text = page.attributedString, text.length > 200,
                  let selection = page.selection(for: NSRange(location: 0, length: text.length)) else { continue }
            let box = page.bounds(for: .cropBox)
            let lines = selection.selectionsByLine().map { $0.bounds(for: page) }.filter { $0.width > 30 && $0.height > 3 }
            guard lines.count > 12 else { continue }
            analyzed += 1
            let leftLines = lines.filter { $0.maxX < box.midX + 10 && $0.midX < box.midX - 20 }.count
            let rightLines = lines.filter { $0.minX > box.midX - 10 && $0.midX > box.midX + 20 }.count
            if leftLines > 7, rightLines > 7, leftLines + rightLines > lines.count * 2 / 3 { columnVotes += 1 }
            bounds.append(contentsOf: lines)
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                guard let font = value as? NSFont, (8...14).contains(font.pointSize) else { return }
                fontCounts[Int(font.pointSize.rounded()), default: 0] += range.length
                let name = (font.familyName ?? font.fontName).lowercased()
                if name.contains("times") || name.contains("serif") || name.contains("cambria") || name.contains("cmr") { serifCount += range.length }
                else { sansCount += range.length }
            }
        }
        if columnVotes > 0, columnVotes * 2 >= analyzed { result.columns = 2 }
        if let size = fontCounts.max(by: { $0.value < $1.value })?.key { result.fontSize = CGFloat(size) }
        result.serif = serifCount >= sansCount
        if !bounds.isEmpty {
            result.left = max(28, min(80, (bounds.map(\.minX).min() ?? 56) - paper.minX))
            result.right = max(28, min(80, paper.maxX - (bounds.map(\.maxX).max() ?? paper.maxX - 56)))
            result.top = max(32, min(80, paper.maxY - (bounds.map(\.maxY).max() ?? paper.maxY - 56)))
            result.bottom = max(32, min(80, (bounds.map(\.minY).min() ?? 56) - paper.minY))
        }
        return result
    }
}
