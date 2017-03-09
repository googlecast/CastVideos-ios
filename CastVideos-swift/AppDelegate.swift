// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import AVFoundation
import GoogleCast

let kPrefPreloadTime = "preload_time_sec"
let kPrefEnableAnalyticsLogging = "enable_analytics_logging"
let kPrefEnableSDKLogging = "enable_sdk_logging"
let kPrefAppVersion = "app_version"
let kPrefSDKVersion = "sdk_version"
let kPrefReceiverAppID = "receiver_app_id"
let kPrefCustomReceiverSelectedValue = "use_custom_receiver_app_id"
let kPrefCustomReceiverAppID = "custom_receiver_app_id"
let kPrefEnableMediaNotifications = "enable_media_notifications"

let kApplicationID: String? = nil
let appDelegate = (UIApplication.shared.delegate as? AppDelegate)

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var enableSDKLogging = false
  var mediaNotificationsEnabled = false
  var firstUserDefaultsSync = false
  var useCastContainerViewController = false

  var window: UIWindow?
  var mediaList: MediaListModel!
  var isCastControlBarsEnabled: Bool {
    get {
      if useCastContainerViewController {
        let castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        return castContainerVC!.miniMediaControlsItemEnabled
      } else {
        let rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        return rootContainerVC!.miniMediaControlsViewEnabled
      }
    }
    set(notificationsEnabled) {
      if useCastContainerViewController {
        var castContainerVC: GCKUICastContainerViewController?
        castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        castContainerVC?.miniMediaControlsItemEnabled = notificationsEnabled
      } else {
        var rootContainerVC: RootContainerViewController?
        rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        rootContainerVC?.miniMediaControlsViewEnabled = notificationsEnabled
      }
    }
  }

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    populateRegistrationDomain()
    let applicationID: String = applicationIDFromUserDefaults()!
    if applicationID == "" {
      // Don't try to go on without a valid application ID - SDK will fail an
      // assert and app will crash.
      return true
    }
    // We are forcing a custom container view controller, but the Cast Container
    // is also available
    useCastContainerViewController = false

    let options = GCKCastOptions(receiverApplicationID: applicationID)
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
    window?.clipsToBounds = true
    setupCastLogging()

    // Set playback category mode to allow playing audio on the video files even
    // when the ringer mute switch is on.
    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
    } catch let setCategoryError {
      print("Error setting audio category: \(setCategoryError.localizedDescription)")
    }

    if useCastContainerViewController {
      let appStoryboard = UIStoryboard(name: "Main", bundle: nil)
      guard let navigationController = appStoryboard.instantiateViewController(withIdentifier: "MainNavigation")
        as? UINavigationController else { return false }
      let castContainerVC = GCKCastContext.sharedInstance().createCastContainerController(for: navigationController)
        as GCKUICastContainerViewController
      castContainerVC.miniMediaControlsItemEnabled = true
      window = UIWindow(frame: UIScreen.main.bounds)
      window?.rootViewController = castContainerVC
      window?.makeKeyAndVisible()
    } else {
      let rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      rootContainerVC?.miniMediaControlsViewEnabled = true
    }

    NotificationCenter.default.addObserver(self, selector: #selector(syncWithUserDefaults),
                                           name: UserDefaults.didChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(presentExpandedMediaControls),
                                           name: NSNotification.Name.gckExpandedMediaControlsTriggered, object: nil)
    firstUserDefaultsSync = true
    syncWithUserDefaults()
    UIApplication.shared.statusBarStyle = .lightContent
    GCKCastContext.sharedInstance().sessionManager.add(self)
    GCKCastContext.sharedInstance().imagePicker = self
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.gckExpandedMediaControlsTriggered,
                                              object: nil)
  }

  func setupCastLogging() {
    let logFilter = GCKLoggerFilter()
    let classesToLog = ["GCKDeviceScanner", "GCKDeviceProvider", "GCKDiscoveryManager", "GCKCastChannel",
                        "GCKMediaControlChannel", "GCKUICastButton", "GCKUIMediaController", "NSMutableDictionary"]
    logFilter.setLoggingLevel(.verbose, forClasses: classesToLog)
    GCKLogger.sharedInstance().filter = logFilter
    GCKLogger.sharedInstance().delegate = self
  }

  func presentExpandedMediaControls() {
    print("present expanded media controls")
    // Segue directly to the ExpandedViewController.
    let navigationController: UINavigationController?
    if useCastContainerViewController {
      let castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
      navigationController = (castContainerVC?.contentViewController as? UINavigationController)
    } else {
      let rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      navigationController = rootContainerVC?.navigationController
    }
    // NOTE: Why aren't we just setting this to nil?
    navigationController?.navigationItem.backBarButtonItem =
        UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    if let appDelegate = appDelegate, appDelegate.isCastControlBarsEnabled == true {
      appDelegate.isCastControlBarsEnabled = false
    }
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }
}

// MARK: - Working with default values
extension AppDelegate {

  func populateRegistrationDomain() {
    let settingsBundleURL = Bundle.main.url(forResource: "Settings", withExtension: "bundle")
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    var appDefaults = [String: Any]()
    loadDefaults(&appDefaults, fromSettingsPage: "Root", inSettingsBundleAt: settingsBundleURL!)
    let userDefaults = UserDefaults.standard
    userDefaults.register(defaults: appDefaults)
    userDefaults.setValue(appVersion, forKey: kPrefAppVersion)
    userDefaults.setValue(kGCKFrameworkVersion, forKey: kPrefSDKVersion)
    userDefaults.synchronize()
  }

  func loadDefaults(_ appDefaults: inout [String: Any], fromSettingsPage plistName: String,
                    inSettingsBundleAt settingsBundleURL: URL) {
    let plistFileName = plistName.appending(".plist")
    let settingsDict = NSDictionary(contentsOf: settingsBundleURL.appendingPathComponent(plistFileName))
    if let prefSpecifierArray = settingsDict?["PreferenceSpecifiers"] as? [[AnyHashable:Any]] {
      for prefItem in prefSpecifierArray {
        let prefItemType = prefItem["Type"] as? String
        let prefItemKey = prefItem["Key"] as? String
        let prefItemDefaultValue = prefItem["DefaultValue"] as? String
        if prefItemType == "PSChildPaneSpecifier" {
          let prefItemFile = prefItem["File"]  as? String
          loadDefaults(&appDefaults, fromSettingsPage: prefItemFile!, inSettingsBundleAt: settingsBundleURL)
        } else if (prefItemKey != nil) && (prefItemDefaultValue != nil) {
          appDefaults[prefItemKey!] = prefItemDefaultValue
        }
      }
    }
  }

  func applicationIDFromUserDefaults() -> String? {
    let userDefaults = UserDefaults.standard
    var prefApplicationID = userDefaults.string(forKey: kPrefReceiverAppID)
    if prefApplicationID == kPrefCustomReceiverSelectedValue {
      prefApplicationID = userDefaults.string(forKey: kPrefCustomReceiverAppID)
    }
    if prefApplicationID == nil {
      let message: String = "You don't seem to have an application ID.\n" +
      "Please fix the app settings."
      showAlert(withTitle: "Invalid Receiver Application ID", message: message)
      return nil
    } else {
      let appIdRegex = try? NSRegularExpression(pattern: "\\b[0-9A-F]{8}\\b", options: [])
      let rangeToCheck = NSRange(location: 0, length: (prefApplicationID?.characters.count ?? 0))
      let numberOfMatches = appIdRegex?.numberOfMatches(in: prefApplicationID!,
                                                        options: [],
                                                        range: rangeToCheck)
      if numberOfMatches == 0 {
        let message: String = "\"\(prefApplicationID)\" is not a valid application ID\n" +
        "Please fix the app settings (should be 8 hex digits, in CAPS)"
        showAlert(withTitle: "Invalid Receiver Application ID", message: message)
        return nil
      }
    }
    return prefApplicationID
  }

  func syncWithUserDefaults() {
    let userDefaults = UserDefaults.standard
    // Forcing no logging from the SDK
    enableSDKLogging = false
    let mediaNotificationsEnabled = userDefaults.bool(forKey: kPrefEnableMediaNotifications)
    GCKLogger.sharedInstance().delegate?.logMessage?("Notifications on? \(mediaNotificationsEnabled)",
                                                     fromFunction: #function)
    if firstUserDefaultsSync || (self.mediaNotificationsEnabled != mediaNotificationsEnabled) {
      self.mediaNotificationsEnabled = mediaNotificationsEnabled
      if useCastContainerViewController {
        let castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        castContainerVC?.miniMediaControlsItemEnabled = mediaNotificationsEnabled
      } else {
        let rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        rootContainerVC?.miniMediaControlsViewEnabled = mediaNotificationsEnabled
      }
    }
    firstUserDefaultsSync = false
  }
}

// MARK: - GCKLoggerDelegate
extension AppDelegate: GCKLoggerDelegate {
  func logMessage(_ message: String, fromFunction function: String) {
    if enableSDKLogging {
      // Send SDK's log messages directly to the console.
      print("\(function)  \(message)")
    }
  }

}

// MARK: - GCKSessionManagerListener
extension AppDelegate: GCKSessionManagerListener {

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    if error == nil {
      Toast.displayMessage("Session ended", for: 3, in: (window?.rootViewController?.view)!)
    } else {
      let message = "Session ended unexpectedly:\n\(error?.localizedDescription)"
      showAlert(withTitle: "Session error", message: message)
    }
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
    let message = "Failed to start session:\n\(error.localizedDescription)"
    showAlert(withTitle: "Session error", message: message)
  }

  func showAlert(withTitle title: String, message: String) {
    // TODO: Pull this out into a class that either shows an AlertVeiw or a AlertController
    let alert = UIAlertView(title: title, message: message,
                            delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
    alert.show()
  }

}

// MARK: - GCKUIImagePicker
extension AppDelegate: GCKUIImagePicker {
  func getImageWith(_ imageHints: GCKUIImageHints, from metadata: GCKMediaMetadata) -> GCKImage? {
    let images = metadata.images
    guard !images().isEmpty else { print("No images available in media metadata."); return nil }
    if images().count > 1 && imageHints.imageType == .background {
      return images()[1] as? GCKImage
    } else {
      return images()[0] as? GCKImage
    }
  }
}
