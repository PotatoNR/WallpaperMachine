import XCTest

@testable import WallpaperMachine

/// The sign-in window shows no address and carries the site's name, so what may load in it is
/// checked against the site: the page stays on Steam's own hosts, frames inside it may load a
/// third-party challenge, and nothing but HTTPS or a blank page loads at all.
final class WebSignInPolicyTests: XCTestCase {
    func testSteamsPageMayBeItsSignInHelpAndSignUpHosts() throws {
        for host in ["steamcommunity.com", "login.steampowered.com", "help.steampowered.com", "store.steampowered.com"] {
            let url = try XCTUnwrap(URL(string: "https://\(host)/login/home/"))
            XCTAssertTrue(WebSignInSite.steam.allows(url, inPage: true), host)
        }
        XCTAssertTrue(WebSignInSite.steam.allows(URL(string: "https://STEAMCOMMUNITY.com:443/login"), inPage: true))
        XCTAssertTrue(WebSignInSite.steam.allows(WebSignInSite.steam.signInURL, inPage: true))
        XCTAssertTrue(WebSignInSite.steam.allows(URL(string: "about:blank"), inPage: true))
    }

    func testNothingElseCanStandInForSteamsPage() {
        for address in [
            "https://example.invalid/login", "https://steamcommunity.com.example.invalid/login",
            "https://notsteamcommunity.com/login", "https://evil.steamcommunity.com/login",
            "https://steamcommunity.com@example.invalid/login", "https://user:password@steamcommunity.com/login",
            "https://steamcommunity.com:8443/login", "http://steamcommunity.com/login",
            "data:text/html,login", "javascript:alert(1)", "file:///tmp/login.html", "steam://login",
            "about:srcdoc",
        ] {
            XCTAssertFalse(WebSignInSite.steam.allows(URL(string: address), inPage: true), address)
        }
        XCTAssertFalse(WebSignInSite.steam.allows(nil, inPage: true))
    }

    func testAChallengeMayLoadInAFrameButNotReplaceThePage() throws {
        let challenge = try XCTUnwrap(URL(string: "https://www.google.com/recaptcha/api2/anchor"))
        XCTAssertTrue(WebSignInSite.steam.allows(challenge, inPage: false))
        XCTAssertFalse(WebSignInSite.steam.allows(challenge, inPage: true))
        XCTAssertTrue(WebSignInSite.steam.allows(URL(string: "about:srcdoc"), inPage: false))
        XCTAssertFalse(WebSignInSite.steam.allows(URL(string: "http://example.invalid"), inPage: false))
    }

    func testPixivsPageMayReachAnyHTTPSSignInProvider() {
        XCTAssertTrue(WebSignInSite.pixiv.allows(URL(string: "https://accounts.google.com/"), inPage: true))
        XCTAssertTrue(WebSignInSite.pixiv.allows(WebSignInSite.pixiv.signInURL, inPage: true))
        XCTAssertFalse(WebSignInSite.pixiv.allows(URL(string: "http://accounts.pixiv.net/login"), inPage: true))
        XCTAssertFalse(WebSignInSite.pixiv.allows(URL(string: "file:///tmp/login.html"), inPage: true))
    }
}
