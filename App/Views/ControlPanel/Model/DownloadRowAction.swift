import Foundation

/// The four things a download's controls do to it, wherever they sit: the Downloads list, a
/// Workshop tile's ring and its inspector, the pixiv inspector and Settings' shared resources.
///
/// It names the key each runs under for the queue the job belongs to, so a control that disables
/// itself while its action is pending reads the same key the action was started under.
enum DownloadRowAction: Equatable, CaseIterable {
  case pause, cancel, resume, retry

  /// The SF Symbol of the action's control, the same wherever it sits. Resume is a down arrow to a
  /// line, never `play.fill`, which starts a rotation or resumes playback; it is not the plain
  /// arrow of a download that waits its turn either, so a paused ring and a waiting one differ.
  var systemImage: String {
    switch self {
    case .pause: "pause.fill"
    case .cancel: "xmark"
    case .resume: "arrow.down.to.line"
    case .retry: "arrow.clockwise"
    }
  }

  /// The key the action runs under for the job `id` of `source`'s queue.
  func key(_ source: DownloadRow.Source, id: String) -> String {
    PanelActionCoordinator.key(name(source), id: id)
  }

  private func name(_ source: DownloadRow.Source) -> String {
    switch (self, source) {
    case (.pause, .steam): "downloadPause"
    case (.cancel, .steam): "downloadCancel"
    case (.resume, .steam): "downloadResume"
    case (.retry, .steam): "downloadRetry"
    case (.pause, .pixiv): "pixivPause"
    case (.cancel, .pixiv): "pixivCancel"
    case (.resume, .pixiv): "pixivResume"
    case (.retry, .pixiv): "pixivRetryDownload"
    }
  }
}
