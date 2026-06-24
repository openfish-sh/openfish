import AppKit
import Combine

/// Where supporters pay, and the price. Openfish is free, open source, and on
/// Homebrew, so this is an honest "pay if you can" purchase — never a gate. Set the
/// checkout URL to the live Polar.sh link once the one-time product is created.
enum SupportLinks {
    /// Polar.sh one-time ($19) checkout for the "Openfish — Lifetime" product.
    static let checkout = URL(string: "https://buy.polar.sh/polar_cl_veuljrMLHBNDAvK7d2qqYlqjOl9HyVvrCgYZ82j3L9R")!
    static let price = "$19"
}

/// Tracks — on this Mac only — whether the user has chipped in, and whether now is a
/// good moment to (gently, once) ask. No accounts and no license validation: paying
/// is honor-system, so the deep link / "I already did" simply flips a local flag.
///
/// The ask follows what the voluntary-payment research favours: wait until the app
/// has demonstrably earned its place (time installed + accepted replies), ask once at
/// a value moment, and never nag or block.
@MainActor
final class SupportStore: ObservableObject {
    static let shared = SupportStore()

    /// Days of use before the first nudge — the free app *is* the trial.
    private let nudgeAfterDays: Double = 14
    /// Accepted replies before the first nudge — only ask once there's clear value.
    private let nudgeAfterValueMoments = 8
    /// After a "Maybe later", wait this long before asking again.
    private let reNudgeAfterDays: Double = 10

    private let defaults = UserDefaults.standard

    /// Published so the menu item can show a supporter state.
    @Published private(set) var hasSupported: Bool

    private let firstLaunch: Double
    private var valueMoments: Int
    private var lastDeclined: Double
    private var suppressed: Bool

    private init() {
        let d = UserDefaults.standard
        hasSupported = d.bool(forKey: Keys.hasSupported)
        valueMoments = d.integer(forKey: Keys.valueMoments)
        lastDeclined = d.double(forKey: Keys.lastDeclined)
        suppressed = d.bool(forKey: Keys.suppressed)
        // Stamp first launch once, so "days installed" is measured from real first use.
        let stored = d.double(forKey: Keys.firstLaunch)
        if stored == 0 {
            firstLaunch = Date().timeIntervalSince1970
            d.set(firstLaunch, forKey: Keys.firstLaunch)
        } else {
            firstLaunch = stored
        }
    }

    /// Record that the user just accepted a generated reply — a moment of value.
    func recordValueMoment() {
        valueMoments += 1
        defaults.set(valueMoments, forKey: Keys.valueMoments)
    }

    /// Whether now is a good moment to show the one-shot nudge.
    var shouldNudge: Bool {
        guard !hasSupported, !suppressed else { return false }
        let now = Date().timeIntervalSince1970
        guard (now - firstLaunch) / 86_400 >= nudgeAfterDays,
              valueMoments >= nudgeAfterValueMoments else { return false }
        if lastDeclined > 0, (now - lastDeclined) / 86_400 < reNudgeAfterDays { return false }
        return true
    }

    /// "Maybe later" — back off and ask again only after a while.
    func declineNudge() {
        lastDeclined = Date().timeIntervalSince1970
        defaults.set(lastDeclined, forKey: Keys.lastDeclined)
    }

    /// The user paid (via the `koifish://supported` deep link) or said they already
    /// had. Honor-system: we just stop asking and show our thanks.
    func markSupported() {
        guard !hasSupported else { return }
        hasSupported = true
        suppressed = true
        defaults.set(true, forKey: Keys.hasSupported)
        defaults.set(true, forKey: Keys.suppressed)
    }

    /// Open the Polar checkout in the browser.
    func openCheckout() {
        NSWorkspace.shared.open(SupportLinks.checkout)
    }

    private enum Keys {
        static let firstLaunch = "support.firstLaunchEpoch"
        static let valueMoments = "support.valueMoments"
        static let hasSupported = "support.hasSupported"
        static let lastDeclined = "support.lastDeclinedEpoch"
        static let suppressed = "support.suppressed"
    }
}
