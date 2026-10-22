//
// AdsConfig.swift
// Veloce
//
// AdMob unit IDs + frequency caps. The only ads file that changes per app.
// Ads are shown only while the user has NOT bought "Remove Ads"
// (former Pro buyers — lifetime or yearly — are ad-free too).
//

import CoreGraphics
import Foundation

enum AdsConfig {

    // MARK: - Ad unit IDs
    // AdMob app ID lives in Veloce/Info.plist (GADApplicationIdentifier):
    //   ca-app-pub-5982140566133654~1358417265  (VeloceAI)
    // DEBUG builds always use Google's test units so we never click our own live ads.

    #if DEBUG
    static let bannerUnitID       = "ca-app-pub-3940256099942544/2934735716"   // Google test banner
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"   // Google test interstitial
    #else
    static let bannerUnitID       = releaseBannerUnitID
    static let interstitialUnitID = releaseInterstitialUnitID
    #endif

    static let releaseBannerUnitID       = "ca-app-pub-5982140566133654/1473308192"   // Veloce Banner - above input bar
    static let releaseInterstitialUnitID = "ca-app-pub-5982140566133654/9975273889"   // Veloce Interstitial - after expenses

    // MARK: - Frequency caps

    /// An interstitial may only follow every Nth qualifying action
    /// (Veloce: a logged expense).
    static let interstitialEveryNActions = 5

    /// Minimum gap between two interstitials.
    static let minSecondsBetweenInterstitials: TimeInterval = 180

    /// Short pause after the qualifying action, so its feedback is seen
    /// before the ad covers the screen.
    static let interstitialPresentationDelay: TimeInterval = 1.0

    /// Pause before the consent form / ATT prompt once the main UI is on screen.
    static let startupDelay: TimeInterval = 1.5

    // MARK: - Layout

    /// Gap between the banner and the input bar.
    static let bannerSpacing: CGFloat = 4
}
