//    The MIT License (MIT)
//
//    Copyright (c) 2015-2018 Dominik Ringler
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import GoogleMobileAds

/**
 SwiftyAd
 
 A singleton class to manage adverts from Google AdMob.
 */
public final class SwiftyAd: NSObject {
    
    // MARK: - Static Properties
    
    /// The shared instance of SwiftyAd using default non costumizable settings
    public static let shared = SwiftyAd()
    
    // MARK: - Properties
    
    /// Delegate callbacks
    public weak var delegate: SwiftyAdDelegate?
    
    /// Ads
    var bannerAdView: GADBannerView?
    var interstitialAd: GADInterstitial?
    var rewardedVideoAd: GADRewardBasedVideoAd?
    
    /// Constraints
    var bannerViewConstraint: NSLayoutConstraint?
    
    /// Init
    let configuration: AdConfiguration
    private var intervalTracker: SwiftyAdIntervalTrackerInput!
    private var mediationManager: SwiftyAdMediation?
    private var consentManager: SwiftyAdConsent!
    private(set) var bannerAnimationDuration = 1.8
    
    #if DEBUG
    //Testdevices in DEBUG mode
    private var testDevices: [Any] = [kGADSimulatorID]
    #endif
    
    // MARK: - Computed Properties
    
    /// Check if user has consent e.g to hide rewarded video button
    public var hasConsent: Bool {
        return consentManager.hasConsent
    }
    
    /// Check if we must ask for consent e.g to hide change consent button in apps settings menu (required GDPR requirement)
    public var isRequiredToAskForConsent: Bool {
        return consentManager.isRequiredToAskForConsent
    }
    
    /// Check if interstitial video is ready (e.g to show alternative ad like an in house ad)
    /// Will try to reload an ad if it returns false.
    public var isInterstitialReady: Bool {
        guard interstitialAd?.isReady == true else {
            print("AdMob interstitial ad is not ready, reloading...")
            loadInterstitialAd()
            return false
        }
        return true
    }
    
    /// Check if reward video is ready (e.g to hide a reward video button)
    /// Will try to reload an ad if it returns false.
    public var isRewardedVideoReady: Bool {
        guard rewardedVideoAd?.isReady == true else {
            print("AdMob reward video is not ready, reloading...")
            loadRewardedVideoAd()
            return false
        }
        return true
    }
    
    /// Remove ads e.g for in app purchases
    public var isRemoved = false {
        didSet {
            guard isRemoved else { return }
            removeBanner()
            interstitialAd?.delegate = nil
            interstitialAd = nil
        }
    }
        
    // MARK: - Init
    
    public init(intervalTracker: SwiftyAdIntervalTrackerInput? = nil,
                mediationManager: SwiftyAdMediation? = nil,
                consentManager: SwiftyAdConsent? = nil,
                bannerAnimationDuration: TimeInterval? = nil,
                testDevices: [Any] = []) {
        // Update configuration
        #if DEBUG
        configuration = .debug
        #else
        configuration = .propertyList
        #endif
        super.init()
        
        // Debug settings
        #if DEBUG
        self.testDevices.append(contentsOf: testDevices)
        #endif
        
        defer {
            print("AdMob SDK version \(GADRequest.sdkVersion())")
        }
        
        // Update properties
        self.intervalTracker = intervalTracker ?? IntervalTracker()
        self.mediationManager = mediationManager
        self.consentManager = consentManager ?? SwiftyAdConsentManager(ids: configuration.ids, configuration: configuration.gdpr)
        
        // Update banner animation duration
        if let bannerAnimationDuration = bannerAnimationDuration {
            self.bannerAnimationDuration = bannerAnimationDuration
        }
        
        // Setup
        #warning("FINISH")
//        setup(with: viewController,
//              delegate: delegate,
//              mediationManager: mediationManager) { }
       
        // Add notification center observers
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceRotated),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    // MARK: - Callbacks
    
    @objc func deviceRotated() {
        bannerAdView?.adSize = UIDevice.current.orientation.isLandscape ? kGADAdSizeSmartBannerLandscape : kGADAdSizeSmartBannerPortrait
    }
    
    // MARK: - Setup
    
    /// Setup swift ad
    ///
    /// - parameter viewController: The view controller that will present the consent alert if needed.
    /// - parameter delegate: A delegate to receive event callbacks. Can also be set manually if needed.
    /// - parameter bannerAnimationDuration: The duration of the banner animation.
    /// - parameter testDevices: The test devices to use when debugging. These will get added in addition to kGADSimulatorID.
    /// - returns handler: A handler that will return a boolean with the consent status.
    public func setup(with viewController: UIViewController,
                      delegate: SwiftyAdDelegate?,
                      bannerAnimationDuration: TimeInterval? = nil,
                      testDevices: [Any] = [],
                      handler: @escaping (_ hasConsent: Bool) -> Void) {
        self.delegate = delegate
    
        // Debug settings
        #if DEBUG
        self.testDevices.append(contentsOf: testDevices)
        #endif
        
        // Update banner animation duration
        if let bannerAnimationDuration = bannerAnimationDuration {
            self.bannerAnimationDuration = bannerAnimationDuration
        }
        
        // Make consent request
        self.consentManager.ask(from: viewController, skipIfAlreadyAuthorized: true) { status in
            self.handleConsentStatusChange(status)
           
            switch status {
            case .personalized, .nonPersonalized:
                self.loadInterstitialAd()
                self.loadRewardedVideoAd()
                handler(true)
            case .adFree, .unknown:
                handler(false)
            }
        }
    }
    
    // MARK: - Ask For Consent
    
    /// Ask for consent. Use this for the consent button that should be e.g in settings.
    ///
    /// - parameter viewController: The view controller that will present the consent form.
    public func askForConsent(from viewController: UIViewController) {
        consentManager.ask(from: viewController, skipIfAlreadyAuthorized: false) { status in
            self.handleConsentStatusChange(status)
        }
    }
    
    // MARK: - Show Banner
    
    /// Show banner ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter position: The position of the banner. Defaults to bottom.
    public func showBanner(from viewController: UIViewController) {
        guard !isRemoved, hasConsent else { return }
        loadBannerAd(from: viewController)
    }
    
    // MARK: - Show Interstitial
    
    /// Show interstitial ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter interval: The interval of when to show the ad, e.g every 4th time the method is called. Defaults to nil.
    public func showInterstitial(from viewController: UIViewController, withInterval interval: Int? = nil) {
        guard !isRemoved, hasConsent else { return }
        guard intervalTracker.canShow(forInterval: interval) else { return }
        guard isInterstitialReady else { return }
        interstitialAd?.present(fromRootViewController: viewController)
    }
    
    // MARK: - Show Reward Video
    
    /// Show rewarded video ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    public func showRewardedVideo(from viewController: UIViewController) {
        guard hasConsent else { return }
        if isRewardedVideoReady {
            rewardedVideoAd?.present(fromRootViewController: viewController)
        } else {
            let alertController = UIAlertController(title: LocalizedString.sorry,
                                                    message: LocalizedString.noVideo,
                                                    preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: LocalizedString.ok, style: .cancel))
            viewController.present(alertController, animated: true)
        }
    }
    
    // MARK: - Remove Banner
    
    /// Remove banner ads
    public func removeBanner() {
        bannerAdView?.delegate = nil
        bannerAdView?.removeFromSuperview()
        bannerAdView = nil
        bannerViewConstraint = nil
    }
}

// MARK: - Make Ad Request

extension SwiftyAd {
    
    func makeRequest() -> GADRequest {
        let request = GADRequest()
        
        // Set debug settings
        #if DEBUG
        request.testDevices = testDevices
        #endif
        
        // Add extras if in EU (GDPR)
        if consentManager.isInEEA {
            
            // Create additional parameters with under age of consent
            var additionalParameters: [String: Any] = ["tag_for_under_age_of_consent": consentManager.isTaggedForUnderAgeOfConsent]
          
            // Update for consent status
            switch consentManager.status {
            case .nonPersonalized:
                additionalParameters["npa"] = "1" // only allow non-personalized ads
            default:
                break
            }
            
            // Create extras
            let extras = GADExtras()
            extras.additionalParameters = additionalParameters
            request.register(extras)
        }
        
        // Return the request
        return request
    }
}

// MARK: - Consent Status Change

private extension SwiftyAd {
    
    func handleConsentStatusChange(_ status: SwiftyAdConsentStatus) {
        delegate?.swiftyAd(self, didChange: status)
        mediationManager?.update(for: status)
    }
}

/// Overrides the default print method so it print statements only show when in DEBUG mode
private func print(_ items: Any...) {
    #if DEBUG
    Swift.print(items)
    #endif
}
