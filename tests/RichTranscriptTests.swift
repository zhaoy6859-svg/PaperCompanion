import AppKit
import WebKit

@main struct RichTranscriptTests {
    static func main() throws {
        _ = NSApplication.shared
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 900))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        web.loadFileURL(root.appendingPathComponent("Chat/index.html"), allowingReadAccessTo: root)
        func evaluate(_ script: String) -> Any? {
            var done = false
            var output: Any?
            web.evaluateJavaScript(script) { value, error in
                output = value
                if let error { print(error) }
                done = true
            }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            assert(done)
            return output
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let answer = #"""
        ## 经验风险
        **平均损失**与参数 $\theta$。
        $$\widehat R_n=\frac{1}{n}\sum_{i=1}^n \ell_i$$

        | 符号 | 含义 |
        | --- | --- |
        | $n$ | 样本数 |

        ```python
        risk = sum(loss) / n
        ```
        <img src=x onerror="window.compromised=true"><script>window.compromised=true</script>
        """#
        let data = try JSONSerialization.data(withJSONObject: ["threads": [["question": "解释公式", "answer": answer, "page": 0]], "pending": false])
        let json = String(data: data, encoding: .utf8)!
        _ = evaluate("window.renderMessages(\(json)); null")
        assert(evaluate("document.querySelectorAll('.katex').length >= 3") as? Bool == true)
        assert(evaluate("document.querySelectorAll('table').length === 1 && document.querySelectorAll('.code-copy').length === 1") as? Bool == true)
        assert(evaluate("!window.compromised && !document.querySelector('.answer img') && !document.querySelector('.answer script')") as? Bool == true)
        assert(evaluate("document.querySelector('pre code').classList.contains('hljs')") as? Bool == true)
        _ = evaluate("scrollTo(0,0); null")
        var captured = false
        web.takeSnapshot(with: nil) { image, _ in
            if let data = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: data) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/pc-rich-test.png"))
            }
            captured = true
        }
        while !captured { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print("PASS: offline Markdown, KaTeX, tables, syntax highlighting, unsafe HTML removal")
    }
}
