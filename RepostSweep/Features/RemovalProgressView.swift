import SwiftUI

struct RemovalProgressView: View {
    @ObservedObject var runner: RemovalRunner
    var onUpgrade: () -> Void
    var onClose: () -> Void

    @State private var confirmStop = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(runner.siteChangeDetail == nil ? "Sweeping" : "Sweep stopped")
                        .font(Typeface.display())
                        .foregroundStyle(Theme.ink)

                    Text(runner.statusText)
                        .font(Typeface.body())
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    ProgressView(value: Double(runner.processed), total: Double(max(runner.total, 1)))
                        .tint(Theme.accent)

                    HStack {
                        stat("Removed", "\(runner.completed)")
                        stat("Didn’t go through", "\(runner.failed)")
                        stat("Left", "\(runner.remainingCount)")
                    }

                    Text(runner.estimateText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)

                    if let current = runner.current {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                Text(current.titleLine)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(3)
                            }
                        }
                    }

                    Text("Each removal waits a couple of seconds, plus a random beat, so TikTok is less likely to throttle the account. You can pause or stop. Stopping does not undo reposts that already came off.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if runner.siteChangeDetail != nil {
                        Text("TikTok’s unrepost action didn’t match this version, so the sweep stopped. Removals that already finished are done. Original videos were not deleted.")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if runner.isFinished {
                        if runner.needsPaywall {
                            PrimaryButton(title: "See plans", systemImage: "sparkles") {
                                onUpgrade()
                            }
                        }
                        PrimaryButton(title: "Done", systemImage: "checkmark") {
                            onClose()
                        }
                    } else {
                        QuietButton(title: runner.isPaused ? "Resume" : "Pause") {
                            runner.togglePause()
                        }
                        Button("Stop") {
                            confirmStop = true
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                }
                .padding(24)
                .readableColumn()
            }
        }
        .confirmationDialog("Stop the sweep?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) {
                runner.stop()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Reposts already removed stay removed.")
        }
        .interactiveDismissDisabled(runner.isFinished == false)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
