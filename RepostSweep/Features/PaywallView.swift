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
                VStack(alignment: .leading, spacing: 18) {
                    Text("Finish the whole tab.")
                        .font(Typeface.title())
                        .foregroundStyle(Theme.ink)
                    Text("The free tier covers \(Monetization.freeRemovalLimit) removals on this device. You’ve used \(freeTier.used). Weekly and yearly plans remove the cap.")
                        .font(Typeface.body())
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if purchases.isSubscribed {
                        SurfaceCard {
                            Text("This Apple ID already has Repost Sweep Premium.")
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
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if purchases.isSubscribed {
                        PrimaryButton(title: "Done", systemImage: "checkmark") {
                            dismiss()
                        }
                    } else if purchases.isPurchasing {
                        ProgressView("Contacting the App Store…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        PrimaryButton(
                            title: purchases.product(id: selectedID) == nil ? "Subscriptions unavailable" : "Continue",
                            systemImage: "sparkles",
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
                        Text("Prices load from the App Store on a signed build that uses the product IDs in Monetization.swift. Until then, the \(freeTier.remaining) free removals still work.")
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
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func planCard(id: String, fallbackTitle: String, badge: String?) -> some View {
        let product = purchases.product(id: id)
        let selected = selectedID == id
        return Button {
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
                                .foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent)
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
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.raised : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
