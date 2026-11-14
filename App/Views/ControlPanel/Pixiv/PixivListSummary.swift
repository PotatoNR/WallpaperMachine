import Foundation

/// The listing's name and its matching result count.
struct PixivListSummary: Equatable {
  let text: String

  /// Search counts stay lower bounds until every accessible source page has been scanned.
  @MainActor
  static func make(_ browse: PixivBrowseState) -> PixivListSummary {
    if browse.isLoading { return PixivListSummary(text: L("Loading pixiv…")) }
    guard browse.hasLoaded else { return PixivListSummary(text: "pixiv") }
    let count = browse.hasExactTotal
      ? L("\(browse.totalCount) results")
      : L("At least \(browse.totalCount) results")
    return PixivListSummary(text: browse.isSearching ? count : "\(browse.query.ranking.title) · \(count)")
  }
}

/// What the page shows in place of the grid while there are no works to show. The first rule that
/// applies wins: loading, then an error, then filters that hide the listing, then nothing found.
enum PixivEmptyState: Equatable {
  case loading
  case error(String)
  case filtersHideAll
  case nothing(searching: Bool)

  /// Nil while there are works on show. A page that has not loaded, is not loading and has no
  /// error is loading: the first visit asks for its list a moment after the page appears.
  static func make(_ browse: PixivBrowseState) -> PixivEmptyState? {
    guard browse.works.isEmpty else { return nil }
    if browse.isLoading || (!browse.hasLoaded && browse.errorMessage == nil) { return .loading }
    if let message = browse.errorMessage { return .error(message) }
    if browse.hiddenCount > 0 || browse.query.ratings.isEmpty {
      return .filtersHideAll
    }
    return .nothing(searching: browse.isSearching)
  }
}
