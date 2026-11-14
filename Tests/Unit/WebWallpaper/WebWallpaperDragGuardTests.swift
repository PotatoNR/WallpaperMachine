import WebKit
import XCTest

@testable import WallpaperMachine

@MainActor
final class WebWallpaperDragGuardTests: XCTestCase {
  /// HTTP CSP applies before document-start scripts, unlike a meta policy parsed later.
  /// Serve it without a network listener or a visible window.
  private final class PageHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
      let response = HTTPURLResponse(
        url: urlSchemeTask.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "text/html", "Content-Security-Policy": "style-src 'none'"])!
      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(Data("""
        <!doctype html><html><head>
        <style>#art { opacity: 0.25; }</style>
        <script>
          const first = new CSSStyleSheet(); first.replaceSync('#box { opacity: 0.25; }');
          document.adoptedStyleSheets = [first];
          const replacement = new CSSStyleSheet(); replacement.replaceSync('#link { opacity: 0.5; }');
          document.adoptedStyleSheets = [replacement];
          window.invalidSheetRejected = false;
          try { document.adoptedStyleSheets = ["not a stylesheet"]; }
          catch (error) { window.invalidSheetRejected = error instanceof TypeError; }
        </script>
        </head><body>
        <img id="art" alt=""><a id="link" href="#x">link</a><div id="box" draggable="true">box</div>
        </body></html>
        """.utf8))
      urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
  }

  func testCSPDoesNotDisableTheGuardAfterAdoptedSheetsAreReplaced() async throws {
    let configuration = WKWebViewConfiguration()
    configuration.setURLSchemeHandler(PageHandler(), forURLScheme: "drag-test")
    for script in WebWallpaperProtocol.userScripts() {
      configuration.userContentController.addUserScript(script)
    }
    let webView = WKWebView(frame: .zero, configuration: configuration)
    defer { webView.stopLoading() }
    webView.load(URLRequest(url: URL(string: "drag-test://wallpaper/index.html")!))

    let deadline = Date().addingTimeInterval(10)
    var result: [String: Any] = [:]
    while Date() < deadline {
      if let value = try? await webView.callAsyncJavaScript(
        """
        if (document.readyState !== "complete" || !document.getElementById("art")) return {};
        return {
          opacity: getComputedStyle(document.getElementById("art")).opacity,
          replacedOpacity: getComputedStyle(document.getElementById("box")).opacity,
          ownOpacity: getComputedStyle(document.getElementById("link")).opacity,
          invalidSheetRejected: window.invalidSheetRejected,
          sources: ["art", "link", "box"].filter(id =>
            getComputedStyle(document.getElementById(id)).getPropertyValue("-webkit-user-drag") !== "none"),
        };
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] {
        result = value
        if result["opacity"] != nil { break }
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(result["opacity"] as? String, "1", "CSP must still block the page's inline styles")
    XCTAssertEqual(result["replacedOpacity"] as? String, "1", "the page must be able to remove its old sheet")
    XCTAssertEqual(result["ownOpacity"] as? String, "0.5", "the page's replacement sheet must still apply")
    XCTAssertEqual(result["invalidSheetRejected"] as? Bool, true, "native stylesheet validation must remain intact")
    XCTAssertEqual(result["sources"] as? [String], [], "CSP must not restore native drag sources")
    XCTAssertNil(webView.window, "This regression must not open a desktop window")
  }
}
