import SwiftUI

/// The newest comments on the item, read-only, from Steam's public thread; the rest are on its
/// Steam page. All of it is Steam's text.
struct WorkshopItemComments: View {
  let item: WorkshopItem

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme

  var body: some View {
    let model = controller.workshopBrowser
    PanelCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Text("Comments")
            .font(.panel(.sectionHeader))
            .accessibilityAddTraits(.isHeader)
          if case .loaded(item.id, let thread) = model.comments, thread.total > 0 {
            CountBadge(count: thread.total)
          }
          Spacer(minLength: 0)
        }
        content(model: model)
        Button("Read all comments on Steam") { model.viewOnSteam(item) }
          .buttonStyle(.panelLink)
          .font(.panel(.callout))
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: item.id) { await model.loadComments(for: item) }
  }

  @ViewBuilder
  private func content(model: WorkshopBrowserModel) -> some View {
    if model.comments.itemID != item.id || model.comments == .loading(itemID: item.id) {
      Text("Loading comments…")
        .font(.panel(.callout))
        .foregroundStyle(theme.surface.muted.color)
    } else if case .failed(_, let message) = model.comments {
      Text(verbatim: message)
        .font(.panel(.callout))
        .foregroundStyle(theme.surface.muted.color)
    } else if case .loaded(_, let thread) = model.comments {
      if thread.comments.isEmpty {
        Text("No comments yet")
          .font(.panel(.callout))
          .foregroundStyle(theme.surface.muted.color)
      } else {
        ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(verbatim: comment.author)
                .font(.panel(.calloutStrong))
                .lineLimit(1)
              if let date = comment.date {
                Text(date, format: .relative(presentation: .named))
                  .font(.panel(.caption))
                  .foregroundStyle(theme.surface.muted.color)
              }
            }
            Text(verbatim: comment.text)
              .font(.panel(.callout))
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
        }
      }
    }
  }
}
