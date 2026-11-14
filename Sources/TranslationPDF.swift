import Foundation

enum TranslationPDF {
    /// Kept as the entry point used by the translation column.
    static func source(doc: PaperDoc, pages: [Int: String], language: String) -> String {
        TranslationTeX.document(doc: doc, pages: pages, language: language)
    }
}
