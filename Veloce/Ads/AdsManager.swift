//
// AdsManager.swift
//
// Google AdMob for users who have not bought "Remove Ads": an anchored banner
// and a frequency-capped interstitial.
//
// Startup order (only after `activate()`, i.e. once the main UI is on screen):
//   GDPR consent (UMP, EEA/UK only) → ATT prompt → MobileAds.start → preload.
//
// Integration (app-agnostic):
//   1. `AdsManager.shared.bind(isAdFree: store.$isAdFree)` once at launch.
//   2. `AdsManager.shared.activate()` when the main UI appears (never during onboarding).
//   3. `AdsManager.shared.recordAction()` after each qualifying user action.
//   4. Put `.adBannerInset()` on each tab's content (banner sits above the tab bar).
//   5. Settings: show "Ad privacy choices" when `privacyOptionsRequired`.
//

import SwiftUI
import UIKit
import Combine
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdsManager: NSObject, ObservableObject {

    static let shared = AdsManager()

    /// False once the user owns "Remove Ads" (or before `bind` is called).
    @Published private(set) var adsEnabled = false
    /// Consent + ATT done and the SDK is started.
    @Published private(set) var isReady = false
    /// Height of the loaded banner (0 while loading / no fill / ads off).
    @Published private(set) var bannerHeight: CGFloat = 0
    /// EEA/UK users must be able to reopen the consent form (shown in Settings).
    @Published private(set) var privacyOptionsRequired = false
    /// True while the software keyboard is on screen — the banner steps aside
    /// so it never sits directly above the keys (accidental-click policy).
    @Published private(set) var isKeyboardVisible = false

    /// Bottom space content must keep free so the banner never covers it.
    var bannerInset: CGFloat {
        adsEnabled && bannerHeight > 0 ? bannerHeight + AdsConfig.bannerSpacing : 0
    }

    private enum Keys {
        static let launchCount            = "ads_launchCount"
        static let actionsSinceInterstitial = "ads_actionsSinceInterstitial"
        static let lastInterstitialAt     = "ads_lastInterstitialAt"
    }

    private let defaults = UserDefaults.standard
    /// The very first launch (onboarding) never shows an interstitial.
    private let isFirstLaunch: Bool

    private var uiReady = false
    private var isStarting = false
    private var interstitial: InterstitialAd?
    private var isLoadingInterstitial = false
    private var isPresentingInterstitial = false
    private var adFreeSubscription: AnyCancellable?
    private var keyboardSubscriptions = Set<AnyCancellable>()

    private override init() {
        let launches = defaults.integer(forKey: Keys.launchCount) + 1
        defaults.set(launches, forKey: Keys.launchCount)
        isFirstLaunch = launches == 1
        super.init()

        let center = NotificationCenter.default
        center.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                // The banner view is torn down while the keyboard is up; it
                // reloads (and reports its height again) once the keyboard hides.
                self?.isKeyboardVisible = true
                self?.bannerHeight = 0
            }
            .store(in: &keyboardSubscriptions)
        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = false }
            .store(in: &keyboardSubscriptions)
    }

    // MARK: - Lifecycle

    /// Connects the purchase state. Ads run only while `isAdFree` emits `false`;
    /// buying "Remove Ads" removes every ad immediately.
    func bind<P: Publisher>(isAdFree: P) where P.Output == Bool, P.Failure == Never {
        adFreeSubscription = isAdFree
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] adFree in self?.setAdsEnabled(!adFree) }
    }

    /// Call once the main UI is on screen (after onboarding), so the consent
    /// form / ATT prompt never cover the onboarding flow.
    func activate() {
        uiReady = true
        startIfNeeded()
    }

    private func setAdsEnabled(_ enabled: Bool) {
        adsEnabled = enabled

        if enabled {
            startIfNeeded()
        } else {
            // Just bought "Remove Ads" → drop everything already loaded.
            interstitial = nil
            bannerHeight = 0
        }
    }

    private func startIfNeeded() {
        guard adsEnabled, uiReady, !isStarting else { return }

        if isReady {
            loadInterstitial()
            return
        }

        isStarting = true
        Task {
            defer { isStarting = false }

            // Let the UI settle before showing the consent form / ATT prompt.
            try? await Task.sleep(nanoseconds: UInt64(AdsConfig.startupDelay * 1_000_000_000))
            guard adsEnabled else { return }

            await gatherConsent()
            await requestTrackingAuthorization()

            guard ConsentInformation.shared.canRequestAds, adsEnabled else { return }

            _ = await MobileAds.shared.start()
            isReady = true
            loadInterstitial()
        }
    }

    // MARK: - Consent (GDPR) + ATT

    private func gatherConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // Network error etc. — previous consent (if any) still applies via `canRequestAds`.
            print("[AdsManager] UMP consent error: \(error.localizedDescription)")
        }
        privacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // The ATT prompt is silently skipped while another system alert (e.g. the
        // notification permission request) keeps the app inactive — wait it out.
        await waitUntilAppIsActive()
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private func waitUntilAppIsActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
            return
        }
    }

    /// Settings → "Ad privacy choices" (only shown when `privacyOptionsRequired`).
    func presentPrivacyOptions() {
        Task {
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            } catch {
                print("[AdsManager] UMP privacy options error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Banner callbacks (AdBannerView)

    func bannerDidLoad(height: CGFloat) {
        bannerHeight = adsEnabled ? height : 0
    }

    func bannerDidFail() {
        bannerHeight = 0
    }

    // MARK: - Interstitial

    /// Call after each qualifying user action (Veloce: a logged expense).
    /// Counts toward the frequency cap, then shows an interstitial if allowed.
    func recordAction() {
        guard adsEnabled else { return }
        actionsSinceInterstitial += 1
        showInterstitialIfAllowed()
    }

    /// Shows the preloaded interstitial only when every rule passes:
    /// ads enabled, not the first launch, at least `interstitialEveryNActions`
    /// actions since the last one, and `minSecondsBetweenInterstitials` elapsed.
    /// Returns true if an ad is about to be presented.
    @discardableResult
    func showInterstitialIfAllowed() -> Bool {
        guard adsEnabled, isReady, !isFirstLaunch, !isPresentingInterstitial,
              actionsSinceInterstitial >= AdsConfig.interstitialEveryNActions,
              !isInterstitialOnCooldown
        else { return false }

        guard interstitial != nil else {
            loadInterstitial()
            return false
        }

        isPresentingInterstitial = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(AdsConfig.interstitialPresentationDelay * 1_000_000_000))
            presentInterstitial()
        }
        return true
    }

    private func presentInterstitial() {
        // Re-check: the user may have bought "Remove Ads" during the delay.
        guard adsEnabled, let ad = interstitial, let vc = Self.topViewController() else {
            isPresentingInterstitial = false
            return
        }
        interstitial = nil
        actionsSinceInterstitial = 0
        lastInterstitialAt = Date()
        ad.present(from: vc)
    }

    private func loadInterstitial() {
        guard adsEnabled, isReady, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true

        Task {
            defer { isLoadingInterstitial = false }
            do {
                let ad = try await InterstitialAd.load(with: AdsConfig.interstitialUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                interstitial = adsEnabled ? ad : nil
            } catch {
                print("[AdsManager] Interstitial load failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persisted frequency state

    private var actionsSinceInterstitial: Int {
        get { defaults.integer(forKey: Keys.actionsSinceInterstitial) }
        set { defaults.set(newValue, forKey: Keys.actionsSinceInterstitial) }
    }

    private var lastInterstitialAt: Date? {
        get { defaults.object(forKey: Keys.lastInterstitialAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastInterstitialAt) }
    }

    private var isInterstitialOnCooldown: Bool {
        guard let last = lastInterstitialAt else { return false }
        return Date().timeIntervalSince(last) < AdsConfig.minSecondsBetweenInterstitials
    }

    // MARK: - Helpers

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

// MARK: - FullScreenContentDelegate

extension AdsManager: FullScreenContentDelegate {

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            self.isPresentingInterstitial = false
            self.loadInterstitial()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd,
                        didFailToPresentFullScreenContentWithError error: Error) {
        print("[AdsManager] Interstitial failed to present: \(error.localizedDescription)")
        Task { @MainActor in
            self.isPresentingInterstitial = false
            self.loadInterstitial()
        }
    }
}
