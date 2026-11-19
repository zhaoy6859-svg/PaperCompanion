import Foundation

@main struct KeyIsolationTests {
    static func main() {
        let prefs = Prefs.shared
        prefs.baseURL = "https://a.example/v1"
        prefs.setKey("key-a", forBaseURL: prefs.baseURL)
        assert(prefs.apiKey == "key-a", "key for A must be used for A")

        prefs.baseURL = "https://b.example/v1"
        assert(prefs.apiKey == "", "switching the URL must not send A's key to B")

        prefs.setKey("key-b", forBaseURL: prefs.baseURL)
        assert(prefs.apiKey == "key-b", "key for B must be used for B")

        prefs.baseURL = "https://a.example/v1"
        assert(prefs.apiKey == "key-a", "switching back must restore A's own key")

        print("PASS: keys are bound to their service origin, never reused across URLs")
    }
}
