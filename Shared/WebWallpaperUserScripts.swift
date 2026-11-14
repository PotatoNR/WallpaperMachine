import WebKit

extension WebWallpaperProtocol {
    /// Every user script a web wallpaper document gets, in the order they run,
    /// for the desktop page and the native screen-saver surface alike so the two
    /// cannot drift apart.
    ///
    /// The file-request fixes go into every frame, because a subframe the page
    /// embeds (an iframe of a project file, a `srcdoc` frame) fetches and loads
    /// project files too and would otherwise see WebKit's status 0. The host
    /// script, with the author API, the audio and media channels and the page's
    /// timing hooks, goes into the main frame only: a subframe is not the
    /// wallpaper, and must neither answer the host nor be asked by it.
    ///
    /// The font aliases (`WebWallpaperFontAliases`) go into every frame of a local page too,
    /// since a subframe sets text in the fonts it names as the wallpaper does, and so does
    /// `requestIdleCallback` (`WebWallpaperIdleCallbacks`), which Chromium has in every frame.
    /// V8's `Error().stack` format (`WebWallpaperErrorStacks`) goes into every frame as well,
    /// first, so the scripts after it build their errors through it like the page.
    ///
    /// The drag guard (`noDragScript`) goes into every frame too, local or remote,
    /// since an image or link in a subframe starts a drag as readily.
    ///
    /// Web workers are out of reach of a user script, so a worker's own `fetch`
    /// keeps WebKit's behaviour.
    static func userScripts(seed: Seed = Seed()) -> [WKUserScript] {
        [
            WKUserScript(
                source: WebWallpaperErrorStacks.script, injectionTime: .atDocumentStart,
                forMainFrameOnly: false),
            WKUserScript(source: compatScript, injectionTime: .atDocumentStart, forMainFrameOnly: false),
            WKUserScript(
                source: WebWallpaperIdleCallbacks.script, injectionTime: .atDocumentStart,
                forMainFrameOnly: false),
            WKUserScript(
                source: WebWallpaperFontAliases.script, injectionTime: .atDocumentStart,
                forMainFrameOnly: false),
            WKUserScript(source: noDragScript, injectionTime: .atDocumentStart, forMainFrameOnly: false),
            WKUserScript(
                source: makeHostScript(seed: seed), injectionTime: .atDocumentStart, forMainFrameOnly: true),
        ]
    }

    /// A wallpaper never starts a drag. The pointer events a desktop page gets are
    /// copies of ones Finder owns, so a drag WebKit began from them (an image, a
    /// link, selected text, a `draggable` element) dropped a copy of the picture
    /// onto the desktop and broke Finder's selection rectangle. Cancelling
    /// `dragstart` before any handler of the page's keeps WebKit from opening the
    /// system drag; the mouse events themselves still reach the page.
    ///
    /// Cancelling alone comes too late: before WebKit fires `dragstart` it empties
    /// the system drag pasteboard for the drag it is about to start. Pressing a
    /// Finder icon over an image of the page and moving it starts Finder's drag and,
    /// a moment later, WebKit's attempt, which wiped the icon's file from the
    /// pasteboard, so the icon could not be dropped anywhere: not moved on the
    /// desktop, into a folder or onto the Trash. `-webkit-user-drag: none` keeps
    /// ordinary images, links and `draggable` elements from becoming drag sources,
    /// so WebKit never prepares their drags or touches the pasteboard. The page
    /// gets no native `dragstart` from those elements. Drags outside this CSS
    /// guard still reach the cancel above, after WebKit has emptied the pasteboard.
    ///
    /// The rule is installed twice, because a page can drop either copy in the
    /// ordinary course of setting up its own styles: an adopted sheet, which a page
    /// assigning `document.adoptedStyleSheets = [its own]` replaces, and a `<style>`
    /// element on the root, which that assignment does not touch. Only a page that
    /// both replaces its adopted sheets and removes the element loses both copies.
    /// If CSP blocks the root sheet, an accessor retains the constructed sheet on
    /// assignment, preserving native validation and the page's own replacements.
    /// The root sheet's early cascade layer outranks even more specific important
    /// page rules. Inline important styles and shadow trees are outside this guard,
    /// as are existing text selections; this is not a security boundary.
    static let noDragScript = """
    window.addEventListener("dragstart", event => event.preventDefault(), true);
    (() => {
      const rule = "@layer { * { -webkit-user-drag: none !important; } }";
      const sheet = new CSSStyleSheet();
      sheet.replaceSync(rule);
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
      const root = document.documentElement;
      if (!root) return;
      const style = document.createElementNS("http://www.w3.org/1999/xhtml", "style");
      style.textContent = rule;
      root.appendChild(style);
      if (!style.sheet) {
        style.remove();
        // A response-header CSP can block the fallback before any page script runs.
        // Keep the constructed sheet on ordinary replacement without relaxing CSP
        // or observing DOM mutations on an animating page.
        const adopted = Object.getOwnPropertyDescriptor(Document.prototype, "adoptedStyleSheets");
        Object.defineProperty(document, "adoptedStyleSheets", {
          configurable: true,
          enumerable: adopted.enumerable,
          get() { return adopted.get.call(this); },
          set(sheets) {
            adopted.set.call(this, sheets);
            const current = adopted.get.call(this);
            if (!current.includes(sheet)) current.unshift(sheet);
          },
        });
      }
    })();
    """
}
