import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID = Monetization.yearlyProductID

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Remove\nthe cap.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.8)
                    Text("\(Monetization.freeRemovalLimit) removals are free on this device. You’ve used \(freeTier.used). Weekly and yearly plans clear the rest.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    feature("checkmark.circle.fill", "Remove every repost you select")
                    feature("clock.arrow.circlepath", "A history of what left the tab")
                    feature("lock.fill", "Original videos stay up")

                    if purchases.isSubscribed {
                        SurfaceCard {
                            Text("Premium is already active on this Apple ID.")
                                .font(Typeface.body())
                                .foregroundStyle(Theme.ink)
                        }
                    } else {
                        planCard(
                            id: Monetization.yearlyProductID,
                            fallbackTitle: "Yearly",
                            badge: purchases.yearlySavingsPercent.map { "Save \($0)%" } ?? "Best value"
                        )
                        planCard(
                            id: Monetization.weeklyProductID,
                            fallbackTitle: "Weekly",
                            badge: nil
                        )
                    }

                    if let purchaseError = purchases.purchaseError {
                        Text(purchaseError)
                            .font(.footnote)
                            .foregroundStyle(Theme.pink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if purchases.isSubscribed {
                        PrimaryButton(title: "Done", systemImage: "checkmark") {
                            dismiss()
                        }
                    } else if purchases.isPurchasing {
                        ProgressView("Contacting the App Store…")
                            .tint(Theme.pink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        PrimaryButton(
                            title: purchases.product(id: selectedID) == nil ? "Subscriptions unavailable" : "Continue",
                            systemImage: nil,
                            enabled: purchases.product(id: selectedID) != nil
                        ) {
                            guard let product = purchases.product(id: selectedID) else { return }
                            Task {
                                await purchases.purchase(product)
                                if purchases.isSubscribed {
                                    dismiss()
                                }
                            }
                        }
                    }

                    Button("Restore purchases") {
                        Task {
                            await purchases.restore()
                            if purchases.isSubscribed {
                                dismiss()
                            }
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .disabled(purchases.isPurchasing)

                    if purchases.products.isEmpty {
                        Text("Prices load from the App Store on a signed build. On this unsigned build the \(freeTier.remaining) free removals still work.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if purchases.isLoadingProducts == false {
                            QuietButton(title: "Try loading plans again") {
                                Task { await purchases.reloadProducts() }
                            }
                        }
                    }

                    Text(LegalCopy.subscriptions)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LegalCopy.notAffiliated)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .readableColumn()
            }
            .background {
                ZStack {
                    Theme.canvas
                    Circle()
                        .fill(Theme.pink.opacity(0.35))
                        .frame(width: 240, height: 240)
                        .blur(radius: 100)
                        .offset(y: -220)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Theme.raised)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.cyan)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
    }

    private func planCard(id: String, fallbackTitle: String, badge: String?) -> some View {
        let product = purchases.product(id: id)
        let selected = selectedID == id
        return Button {
            Haptics.select()
            selectedID = id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product?.displayName ?? fallbackTitle)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.pink)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.map { purchases.priceLine(for: $0) } ?? "Price from the App Store")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.pink : Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Theme.pink : Theme.line, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
