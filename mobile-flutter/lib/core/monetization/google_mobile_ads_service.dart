// GoogleMobileAdsService — production AdService implementation using
// the google_mobile_ads package. Shows banner ads on free-tier screens
// and an interstitial during course download.
//
// Test ad unit IDs from Google (replace with production IDs before
// release — KAN-198):
//   Banner:       ca-app-pub-3940256099942544/2934735716
//   Interstitial: ca-app-pub-3940256099942544/4411468910

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

class GoogleMobileAdsService implements AdService {
  GoogleMobileAdsService();

  // Test ad unit IDs — KAN-198 will swap these for production.
  static String get _bannerAdUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  static String get _interstitialAdUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  bool _subscribed = false;
  bool _initialized = false;
  InterstitialAd? _interstitialAd;
  bool _hasShownInterstitialThisSession = false;

  @override
  bool get bannerVisible => !_subscribed;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  @override
  void setSubscribed(bool subscribed) {
    _subscribed = subscribed;
  }

  @override
  Widget bannerAd() {
    if (_subscribed) return const SizedBox.shrink();
    return SizedBox(
      height: 50,
      child: _BannerAdWidget(adUnitId: _bannerAdUnitId),
    );
  }

  /// Preloads an interstitial ad. Call early (e.g. when the course
  /// search screen loads) so it's ready when the user taps a result.
  void loadInterstitial() {
    if (_subscribed || _interstitialAd != null) return;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (_) => _interstitialAd = null,
      ),
    );
  }

  /// Shows the preloaded interstitial if conditions are met:
  /// free tier, ad loaded, hasn't shown this session.
  /// Returns true if the ad was shown.
  bool showInterstitialIfReady() {
    if (_subscribed ||
        _interstitialAd == null ||
        _hasShownInterstitialThisSession) {
      return false;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _interstitialAd = null;
      },
    );
    _interstitialAd!.show();
    _hasShownInterstitialThisSession = true;
    return true;
  }

  @override
  Future<void> requestReview() async {
    // TODO: wire in_app_review when ready
  }

  @override
  Future<void> dispose() async {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}

/// Stateful widget that manages a single BannerAd lifecycle.
class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget({required this.adUnitId});
  final String adUnitId;

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd == null || !_isLoaded) {
      return const SizedBox(height: 50);
    }
    return SizedBox(
      height: 50,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
