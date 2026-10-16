import Foundation

struct PrivacySection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

/// User-facing privacy and affiliation copy. The same statements are repeated
/// in onboarding, the paywall, and settings so the disclaimer is hard to miss.
enum LegalCopy {
    static let notAffiliated = "Repost Sweep is not affiliated with, endorsed by, or sponsored by TikTok or ByteDance."

    static let password = "You continue in the TikTok app. Repost Sweep never receives, reads, or stores your password."

    static let session = "The sign-in session stays in the in-app browser on this device. Signing out clears that browser’s website data. Cookies are not copied out of it."

    static let removals = "Removing a repost only takes that video off your reposts tab. It does not delete the original video, and it does not change the creator’s post."

    static let subscriptions = "Payment is charged to your Apple ID at confirmation. A subscription renews automatically unless you cancel at least 24 hours before the end of the current period. Manage or cancel it in your App Store account settings."

    static let privacySections: [PrivacySection] = [
        PrivacySection(title: "Not affiliated with TikTok", body: notAffiliated),
        PrivacySection(title: "Password", body: password),
        PrivacySection(title: "Session", body: session),
        PrivacySection(title: "What removal does", body: removals),
        PrivacySection(
            title: "Subscriptions",
            body: "Purchases are processed by Apple. Repost Sweep does not receive your card number. The free-removal counter is stored on this device with UserDefaults and is not sent to a server."
        ),
        PrivacySection(
            title: "Data this build collects",
            body: "This build has no analytics SDK and no account server. TikTok’s website, loaded in the in-app browser, is governed by TikTok’s own privacy policy."
        )
    ]
}
