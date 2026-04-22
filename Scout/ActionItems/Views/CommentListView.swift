import SwiftUI

/// Inline threaded comments under a task. Editorial voice: `> scout` for
/// SCOUT-generated lines, `// user` for human replies, in mono; comment
/// body in serif. Sits in a sunk panel with a left hairline rule.
struct CommentListView: View {
    let comments: [TaskComment]

    var body: some View {
        if comments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(comments, id: \.self) { c in
                    commentRow(c)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Paper.sunk.opacity(0.6))
            .overlay(alignment: .leading) {
                Rectangle().fill(DS.Rule.hard).frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func commentRow(_ c: TaskComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(markGlyph(for: c.author))
                .font(DS.mono(11, weight: .medium))
                .foregroundStyle(DS.Ink.p4)
                .padding(.top, 2)
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.author)
                        .font(DS.sans(12, weight: .medium))
                        .foregroundStyle(authorColor(c.author))
                    if !c.timestamp.isEmpty {
                        Text(c.timestamp)
                            .font(DS.mono(11))
                            .foregroundStyle(DS.Ink.p4)
                    }
                }
                InlineMarkdownText(c.text)
                    .font(DS.serif(13))
                    .foregroundStyle(DS.Ink.p3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func markGlyph(for author: String) -> String {
        let a = author.lowercased()
        if a == "scout" || a.contains("briefing") || a.contains("dreaming") { return ">" }
        let userAuthor = (UserDefaults.standard.string(forKey: "authorName") ?? "user").lowercased()
        if a == userAuthor { return "//" }
        return "·"
    }

    private func authorColor(_ author: String) -> Color {
        let a = author.lowercased()
        if a == "scout" || a.contains("briefing") || a.contains("dreaming") { return DS.Accent.ink }
        return DS.Ink.p2
    }
}
