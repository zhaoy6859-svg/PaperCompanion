import AppKit
import WebKit

final class RichTranscript: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private let web: WKWebView
    private var ready = false
    private var payload: [String: Any] = [:]
    var onPage: ((Int) -> Void)?
    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        configuration.userContentController.add(self, name: "chat")
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: leadingAnchor),web.trailingAnchor.constraint(equalTo: trailingAnchor),web.topAnchor.constraint(equalTo: topAnchor),web.bottomAnchor.constraint(equalTo: bottomAnchor)])
        let candidates = [Bundle.main.resourceURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")].compactMap { $0 }
        if let root = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Chat/index.html").path) }) {
            web.loadFileURL(root.appendingPathComponent("Chat/index.html"), allowingReadAccessTo: root)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func render(threads: [AskThread], draft: String = "", question: String = "", pending: Bool = false, streaming: Bool = false, page: Int = 0, error: Bool = false) {
        payload = ["threads": threads.map { ["question": $0.question, "answer": $0.answer, "quote": $0.quote ?? "", "page": $0.page, "created": $0.createdAt.timeIntervalSince1970] as [String: Any] }, "draft": draft, "question": question, "pending": pending, "streaming": streaming, "page": page, "error": error]
        update()
    }
    private func update() {
        guard ready, !payload.isEmpty else { return }
        web.callAsyncJavaScript("window.renderMessages(payload)", arguments: ["payload": payload], in: nil, in: .page) { result in
            if case .failure(let error) = result { Debug.log("chat render: \(error)") }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Debug.log("chat webview loaded")
        ready = true
        update()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Debug.log("chat webview failed: \(error.localizedDescription)")
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "copy", let text = body["value"] as? String {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        } else if action == "page", let page = body["value"] as? Int, page >= 0 { onPage?(page) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
    }
    func snapshot(to url: URL, completion: @escaping () -> Void) {
        Debug.log("chat snapshot requested bounds=\(web.bounds) ready=\(ready)")
        web.takeSnapshot(with: nil) { image, error in
            Debug.log("chat snapshot done image=\(image != nil) error=\(error?.localizedDescription ?? "-")")
            if let image {
                let width = max(1, Int(image.size.width * 2))
                let height = max(1, Int(image.size.height * 2))
                if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 0, bitsPerPixel: 0) {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
                    NSGraphicsContext.restoreGraphicsState()
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: url)
                    }
                }
            }
            completion()
        }
    }
}
