import SwiftUI

struct SiteChangeView: View {
    @EnvironmentObject private var session: TikTokWebSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("TikTok changed the page this uses.")
                        .font(Typeface.title())
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Repost Sweep reads and removes reposts through the TikTok website you’re signed into. That page no longer matches this version, so the app stopped instead of guessing.")
                        .font(Typeface.body())
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    section("Your account", [
                        "Your password never comes to Repost Sweep.",
                        "Removals that already finished are done.",
                        "Original videos were not deleted.",
                        "Nothing else on the account was changed."
                    ])

                    section("Why this happens", [
                        "TikTok updates its website without notice. The repost list and the unrepost action are part of that site, not a public API.",
                        "When the response shape changes, the app can no longer tell a repost removal from something else, so it refuses to continue."
                    ])

                    section("What to do", [
                        "Install the next version of Repost Sweep, sign in again, and retry.",
                        "If you already have the latest version, wait and try once more. The change may still be rolling out.",
                        "You can also remove a repost by hand: open the video on TikTok, tap Share, then Remove repost."
                    ])

                    if let detail = session.siteChangeMessage, detail.isEmpty == false {
                        DisclosureGroup {
                            Text(detail)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        } label: {
                            Text("Technical detail")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        }
                    }

                    Text(LegalCopy.notAffiliated)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    PrimaryButton(title: "Close", systemImage: "checkmark") {
                        dismiss()
                    }
                }
                .padding(20)
                .readableColumn()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("What broke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typeface.headline())
                .foregroundStyle(Theme.ink)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(line)
                        .font(Typeface.body())
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
