import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var freeTier: FreeTierStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID = Monetization.yearlyProductID
    @State private var trialOn = true
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        AppGlyph(size: 64)
                        Text("Remove\nthe cap.")
                            .font(Typeface.largeTitle)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(Monetization.freeRemovalLimit) removals are free on this device. You’ve used \(freeTier.used). A plan clears the rest.")
                            .font(Typeface.body)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("Remove every repost you select")
                        benefit("A history of what left the tab")
                        benefit("Original videos stay up")
                    }

                    if purchases.isSubscribed {
                        SurfaceCard {
                            Text("Premium is already active on this Apple ID.")
                                .font(Typeface.body)
                                .foregroundStyle(Theme.ink)
                        }
                    } else {
                        VStack(spacing: 16) {
                            planCard(
                                id: Monetization.yearlyProductID,
                                fallbackTitle: "Yearly",
                                badge: trialOn ? "3-day free trial" : (purchases.yearlySavingsPercent.map { "Save \($0)%" } ?? "Best value")
                            )
                            planCard(
                                id: Monetization.weeklyProductID,
                                fallbackTitle: "Weekly",
                                badge: nil
                            )
                        }
                        SurfaceCard {
                            Toggle(isOn: $trialOn) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("3-day free trial")
                                        .font(Typeface.secondary)
                                        .foregroundStyle(Theme.ink)
                                    Text(selectedID == Monetization.yearlyProductID ? "On the yearly plan" : "Switch to yearly to use it")
                                        .font(Typeface.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .tint(Theme.pink)
                        }
                    }

                    if let purchaseError = purchases.purchaseError {
                        Text(purchaseError)
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.pink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if purchases.products.isEmpty && purchases.isSubscribed == false {
                        Text("Prices load from the App Store on a signed build. On this unsigned build the \(freeTier.remaining) free removals still work.")
                            .font(Typeface.caption)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if purchases.isLoadingProducts == false {
                            QuietButton(title: "Try loading plans again") {
                                Task { await purchases.reloadProducts() }
                            }
                        }
                    }

                    Text(LegalCopy.subscriptions)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LegalCopy.notAffiliated)
                        .font(Typeface.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableColumn()
            }
            .background(ScreenBackdrop())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(Theme.card, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomBar {
                    if purchases.isSubscribed {
                        PrimaryButton(title: "Done", systemImage: "checkmark") {
                            dismiss()
                        }
                    } else if purchases.isPurchasing {
                        ProgressView("Contacting the App Store…")
                            .tint(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.buttonHeight)
                    } else {
                        PrimaryButton(title: ctaTitle, enabled: purchases.product(id: selectedID) != nil) {
                            guard let product = purchases.product(id: selectedID) else { return }
                            Task {
                                await purchases.purchase(product)
                                if purchases.isSubscribed {
                                    dismiss()
                                }
                            }
                        }
                    }
                    HStack(spacing: 18) {
                        Button("Restore") {
                            Task {
                                await purchases.restore()
                                if purchases.isSubscribed {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(purchases.isPurchasing)
                        Button("Terms") { showTerms = true }
                        Button("Privacy") { showPrivacy = true }
                    }
                    .font(Typeface.caption)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: trialOn) { _ in
                Haptics.select()
            }
            .onChange(of: selectedID) { _ in
                Haptics.select()
            }
            .sheet(isPresented: $showTerms) {
                LegalTextSheet(title: "Terms", text: LegalCopy.subscriptions)
                    .sweepSheetChrome()
            }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack {
                    PrivacyView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showPrivacy = false }
                            }
                        }
                }
                .sweepSheetChrome()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var ctaTitle: String {
        if purchases.product(id: selectedID) == nil {
            return "Subscriptions unavailable"
        }
        if trialOn && selectedID == Monetization.yearlyProductID {
            return "Start 3-day free trial"
        }
        return "Continue"
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            Text(text)
                .font(Typeface.body)
                .foregroundStyle(Theme.ink)
        }
    }

    private func planCard(id: String, fallbackTitle: String, badge: String?) -> some View {
        let product = purchases.product(id: id)
        let selected = selectedID == id
        return Button {
            withAnimation(Motion.spring) {
                selectedID = id
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.displayName ?? fallbackTitle)
                        .font(Typeface.title)
                        .foregroundStyle(Theme.ink)
                    Text(product.map { purchases.priceLine(for: $0) } ?? "Price from the App Store")
                        .font(Typeface.secondary)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                SelectionCircle(selected: selected)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.cyan.opacity(selected ? 0.1 : 0),
                                        Theme.pink.opacity(selected ? 0.12 : 0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.line), lineWidth: selected ? CGFloat(1.5) : CGFloat(1))
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.pink, in: Capsule())
                        .offset(y: -10)
                        .padding(.trailing, 14)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LegalTextSheet: View {
    var title: String
    var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(Typeface.body)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.margin)
                    .readableColumn()
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
