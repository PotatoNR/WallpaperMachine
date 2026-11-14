import Foundation
import XCTest

@testable import WallpaperMachine

@MainActor
final class PixivFilteredPaginationTests: XCTestCase {
    private func store(_ transport: any PixivTransport) -> PixivStore {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: library) }
        return PixivStore(
            service: PixivService(transport: transport, minimumInterval: .zero),
            packager: PixivWallpaperPackager(library: library) { data, _ in data },
            sessions: PixivMemorySessionStore())
    }

    private func settled(_ store: PixivStore) async throws {
        let deadline = Date().addingTimeInterval(5)
        while store.isLoading {
            if Date() >= deadline { XCTFail("The listing did not settle"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private nonisolated static func page(_ url: URL) -> Int {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "p" }?.value.flatMap(Int.init) ?? 1
    }

    func testRankingCompactsMatchesAcrossEmptySourcePagesAndRefiltersFromCache() async throws {
        let transport = PixivFixtureTransport { url in
            let page = Self.page(url)
            let entries = (1...50).map { index in
                let id = (page - 1) * 50 + index
                return PixivFixtures.rankingEntry(
                    .init(id: id, width: page == 2 ? 1080 : 3840, height: 2160), rank: id)
            }
            return PixivFixtures.ranking(entries, page: page, total: 150)
        }
        let store = store(transport)
        let query = PixivQuery(orientation: .landscape, minimumSize: .ultraHD)
        store.apply(query)
        try await settled(store)
        XCTAssertEqual(store.works.map(\.id), (1...50).map(String.init))
        XCTAssertEqual(store.totalCount, 100)
        XCTAssertEqual(store.totalPages, 2)
        XCTAssertTrue(store.hasExactTotal)
        store.loadPage(2)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.works.map(\.id), (101...150).map(String.init))
        XCTAssertEqual(transport.requests.map(Self.page), [1, 2, 3])

        store.apply(PixivQuery(orientation: .portrait))
        XCTAssertEqual(store.page, 1)
        XCTAssertEqual(store.totalPages, 1)
        XCTAssertEqual(store.works.map(\.id), (51...100).map(String.init))
        store.apply(PixivQuery())
        XCTAssertEqual(store.totalPages, 3)
        XCTAssertEqual(store.totalCount, 150)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testSearchFillsPagesWithLookaheadWithoutClaimingAnExactTotal() async throws {
        let transport = PixivFixtureTransport { url in
            let page = Self.page(url)
            let entries = (1...60).map { index in
                PixivFixtures.searchEntry(.init(id: (page - 1) * 60 + index, sanity: index <= 30 ? 2 : 4))
            }
            return PixivFixtures.search(entries, total: 300, lastPage: 5)
        }
        let store = store(transport)
        store.apply(PixivQuery(text: "sky"))
        try await settled(store)
        XCTAssertEqual(store.works.count, 60)
        XCTAssertEqual(store.works.map(\.id), ((1...30).map(String.init) + (61...90).map(String.init)))
        XCTAssertEqual(transport.requests.map(Self.page), [1, 2, 3])
        XCTAssertFalse(store.hasExactTotal)
        store.loadPage(2)
        try await settled(store)
        XCTAssertEqual(store.works.map(\.id), ((121...150).map(String.init) + (181...210).map(String.init)))
        XCTAssertTrue(store.hasExactTotal)
        XCTAssertEqual(store.totalCount, 150)
        XCTAssertEqual(store.totalPages, 3)
        store.loadPage(3)
        XCTAssertEqual(store.works.map(\.id), (241...270).map(String.init))
        store.loadPage(1)
        XCTAssertEqual(store.works.count, 60)
        XCTAssertEqual(transport.requests.count, 5)
    }

    func testFailedRefillIsAnErrorAndRetryReusesSuccessfulSourcePages() async throws {
        let failing = LockedFlag()
        failing.value = true
        let transport = PixivFixtureTransport { url in
            let page = Self.page(url)
            if page == 2 && failing.value { throw PixivFailure(code: .status(429)) }
            return PixivFixtures.ranking([
                PixivFixtures.rankingEntry(.init(id: page, sexual: page == 1 ? 1 : 0), rank: page)
            ], page: page, total: 100)
        }
        let store = store(transport)
        store.apply(PixivQuery())
        try await settled(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.hasLoaded)
        failing.value = false
        store.retry()
        try await settled(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.works.map(\.id), ["2"])
        XCTAssertEqual(store.totalPages, 1)
        XCTAssertEqual(transport.requests.map(Self.page), [1, 2, 2])
    }

    func testDuplicateWorksAndFullyHiddenPagesDoNotCreateExtraDisplayPages() async throws {
        let transport = PixivFixtureTransport { url in
            let page = Self.page(url)
            return PixivFixtures.ranking([
                PixivFixtures.rankingEntry(.init(id: 1, sexual: 1), rank: 1),
                PixivFixtures.rankingEntry(.init(id: 2), rank: 2),
            ], page: page, total: 150)
        }
        let store = store(transport)
        store.apply(PixivQuery())
        try await settled(store)
        XCTAssertEqual(store.works.map(\.id), ["2"])
        XCTAssertEqual(store.hiddenCount, 1)
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertEqual(store.totalPages, 1)
        store.apply(PixivQuery(minimumSize: .ultraHD))
        XCTAssertTrue(store.works.isEmpty)
        XCTAssertTrue(store.hasExactTotal)
        XCTAssertEqual(store.totalCount, 0)
        XCTAssertEqual(store.totalPages, 1)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testNoRatingsDoesNotScanTheNetwork() async throws {
        let transport = PixivFixtureTransport { _ in throw PixivFailure(code: .status(429)) }
        let store = store(transport)
        store.apply(PixivQuery(ratings: []))
        XCTAssertTrue(store.hasLoaded)
        XCTAssertTrue(store.hasExactTotal)
        XCTAssertTrue(store.works.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFilterChangesWhileLoadingPublishOnlyTheNewestMatches() async throws {
        let gate = PixivGate()
        defer { gate.open() }
        let fixture = PixivFixtureTransport { url in
            let page = Self.page(url)
            return PixivFixtures.ranking([
                PixivFixtures.rankingEntry(.init(id: page * 10, width: 3840, height: 2160), rank: 1),
                PixivFixtures.rankingEntry(.init(id: page * 10 + 1, width: 2160, height: 3840), rank: 2),
            ], page: page, total: 100)
        }
        let store = store(PixivHeldTransport(fixture: fixture, listings: gate))
        store.apply(PixivQuery(orientation: .landscape))
        let deadline = Date().addingTimeInterval(5)
        while gate.waiting == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(gate.waiting, 1)
        store.apply(PixivQuery(orientation: .portrait))
        gate.open()
        try await settled(store)
        XCTAssertEqual(store.committedQuery?.orientation, .portrait)
        XCTAssertEqual(store.works.map(\.id), ["11", "21"])
        XCTAssertEqual(fixture.requests.map(Self.page), [1, 2])
    }

    func testAnExactlyFullSearchPageDoesNotOfferAnEmptyNextPage() async throws {
        let transport = PixivFixtureTransport { url in
            let page = Self.page(url)
            return PixivFixtures.search(
                (1...60).map {
                    PixivFixtures.searchEntry(.init(id: (page - 1) * 60 + $0, sanity: page == 1 ? 2 : 4))
                }, total: 180, lastPage: 3)
        }
        let store = store(transport)
        store.apply(PixivQuery(text: "sky"))
        try await settled(store)
        XCTAssertEqual(store.works.count, 60)
        XCTAssertEqual(store.totalPages, 1)
        XCTAssertTrue(store.hasExactTotal)
        XCTAssertEqual(transport.requests.count, 3)
    }
}
