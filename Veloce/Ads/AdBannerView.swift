//
// AdBannerView.swift
// Veloce
//
// Standard anchored AdMob banner (320×50). Renders nothing for ad-free users
// or while the keyboard is up, and collapses to 0 height until an ad has
// actually loaded.
//

import SwiftUI
import UIKit
import GoogleMobileAds

struct AdBannerView: View {

    @ObservedObject private var ads = AdsManager.shared

    var body: some View {
        if ads.adsEnabled && ads.isReady && !ads.isKeyboardVisible {
            let size = AdSizeBanner.size

            // The banner view itself always keeps its full 320×50 frame — the SDK
            // rejects a load from a zero-height view ("Invalid ad width or height").
            // Only the outer slot collapses until an ad has actually loaded.
            BannerRepresentable()
                .frame(width: size.width, height: size.height)
                .frame(height: ads.bannerHeight > 0 ? size.height : 0, alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity)
                .padding(.bottom, ads.bannerHeight > 0 ? AdsConfig.bannerSpacing : 0)
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdsConfig.bannerUnitID
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdsManager.shared.bannerDidLoad(height: bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("[AdsManager] Banner load failed: \(error.localizedDescription)")
            AdsManager.shared.bannerDidFail()
        }
    }
}

// MARK: - Tab content inset

extension View {
    /// Pins the banner to the bottom of the content and shrinks the content
    /// so nothing hides behind the ad.
    func adBannerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            AdBannerView()
                // Full-width bar behind the 320pt banner so scrolling content
                // never shows through beside it (collapses with the banner).
                .background(.bar)
        }
    }
}
