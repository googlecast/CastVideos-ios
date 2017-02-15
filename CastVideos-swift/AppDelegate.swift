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

let kPrefPreloadTime: String = "preload_time_sec"

let kPrefEnableAnalyticsLogging: String = "enable_analytics_logging"

let kPrefEnableSDKLogging: String = "enable_sdk_logging"

let kPrefAppVersion: String = "app_version"

let kPrefSDKVersion: String = "sdk_version"

let kPrefReceiverAppID: String = "receiver_app_id"

let kPrefCustomReceiverSelectedValue: String = "use_custom_receiver_app_id"

let kPrefCustomReceiverAppID: String = "custom_receiver_app_id"

let kPrefEnableMediaNotifications: String = "enable_media_notifications"

let kApplicationID: String? = nil

let appDelegate = (UIApplication.shared.delegate as? AppDelegate)

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GCKLoggerDelegate, GCKSessionManagerListener, GCKUIImagePicker {
  var enableSDKLogging = false
  var mediaNotificationsEnabled = false
  var firstUserDefaultsSync = false
  var useCastContainerViewController = false

  var window: UIWindow?
  var mediaList: MediaListModel!
  var isCastControlBarsEnabled: Bool {
    get {
      if useCastContainerViewController {
        if let castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController) {
          return castContainerVC.miniMediaControlsItemEnabled
        }
      }
      else {
        if let rootContainerVC = (window?.rootViewController as? RootContainerViewController) {
          return rootContainerVC.isMiniMediaControlsViewEnabled
        }
      }
    }
    set(notificationsEnabled) {
      if useCastContainerViewController {
        var castContainerVC: GCKUICastContainerViewController?
        castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        castContainerVC?.miniMediaControlsItemEnabled = notificationsEnabled
      }
      else {
        var rootContainerVC: RootContainerViewController?
        rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        rootContainerVC?.isMiniMediaControlsViewEnabled = notificationsEnabled
      }
    }
  }


  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
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
    let logFilter = GCKLoggerFilter()
    logFilter.exclusive = true
    logFilter.addClassNames(["GCKDeviceScanner", "GCKDeviceProvider", "GCKDiscoveryManager", "GCKCastChannel", "GCKMediaControlChannel", "GCKUICastButton", "GCKUIMediaController", "NSMutableDictionary"])
    GCKLogger.sharedInstance().filter = logFilter
    GCKLogger.sharedInstance().delegate = self
    // Set playback category mode to allow playing audio on the video files even
    // when the ringer mute switch is on.

    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
    } catch let setCategoryError {
      print("Error setting audio category: \(setCategoryError.localizedDescription)")
    }
    NotificationCenter.default.addObserver(self, selector: #selector(syncWithUserDefaults), name: UserDefaults.didChangeNotification, object: nil)
    if useCastContainerViewController {
      let appStoryboard = UIStoryboard(name: "Main", bundle: nil)
      let navigationController = appStoryboard.instantiateViewController(withIdentifier: "MainNavigation") as! UINavigationController
      var castContainerVC: GCKUICastContainerViewController?
      castContainerVC = GCKCastContext.sharedInstance().createCastContainerController(for: navigationController)
      castContainerVC?.miniMediaControlsItemEnabled = true
      window = UIWindow(frame: UIScreen.main.bounds)
      window?.rootViewController = castContainerVC
      window?.makeKeyAndVisible()
    }
    else {
      var rootContainerVC: RootContainerViewController?
      rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      rootContainerVC?.isMiniMediaControlsViewEnabled = true
    }
    NotificationCenter.default.addObserver(self, selector: #selector(presentExpandedMediaControls), name: NSNotification.Name.gckExpandedMediaControlsTriggered, object: nil)
    firstUserDefaultsSync = true
    syncWithUserDefaults()
    UIApplication.shared.statusBarStyle = .lightContent
    GCKCastContext.sharedInstance().sessionManager.add(self)
    GCKCastContext.sharedInstance().imagePicker = self
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.gckExpandedMediaControlsTriggered, object: nil)
  }

  func populateRegistrationDomain() {
    let settingsBundleURL: URL? = Bundle.main.url(forResource: "Settings", withExtension: "bundle")
    let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let appDefaults = [String: Any]()
    loadDefaults(appDefaults, fromSettingsPage: "Root", inSettingsBundleAt: settingsBundleURL!)
    let userDefaults = UserDefaults.standard
    userDefaults.register(defaults: appDefaults)
    userDefaults.setValue(appVersion, forKey: kPrefAppVersion)
    userDefaults.setValue(kGCKFrameworkVersion, forKey: kPrefSDKVersion)
    userDefaults.synchronize()
  }

  func loadDefaults(_ appDefaults: [AnyHashable: Any], fromSettingsPage plistName: String, inSettingsBundleAt settingsBundleURL: URL) {
    let plistFileName = URL(fileURLWithPath: plistName).appendingPathExtension("plist").absoluteString
    let settingsDict = NSDictionary(contentsOf: settingsBundleURL.appendingPathComponent(plistFileName))
    var prefSpecifierArray = (settingsDict?["PreferenceSpecifiers"] as? Array)
    for prefItem in prefSpecifierArray {
      var prefItemType: String = prefItem["Type"]
      var prefItemKey: String = prefItem["Key"]
      var prefItemDefaultValue: String = prefItem["DefaultValue"]
      if (prefItemType == "PSChildPaneSpecifier") {
        var prefItemFile: String = prefItem["File"]
        loadDefaults(appDefaults, fromSettingsPage: prefItemFile, inSettingsBundleAt: settingsBundleURL)
      }
      else if prefItemKey && prefItemDefaultValue {
        appDefaults[prefItemKey] = prefItemDefaultValue
      }
    }
  }

  func applicationIDFromUserDefaults() -> String? {
    let userDefaults = UserDefaults.standard
    var prefApplicationID: String? = userDefaults.string(forKey: kPrefReceiverAppID)
    if (prefApplicationID == kPrefCustomReceiverSelectedValue) {
      prefApplicationID = userDefaults.string(forKey: kPrefCustomReceiverAppID)
    }
    let appIdRegex = try? NSRegularExpression(pattern: "\\b[0-9A-F]{8}\\b", options: [])
    let numberOfMatches: Int = (appIdRegex?.numberOfMatches(in: prefApplicationID!, options: [], range: NSRange(location: 0, length: (prefApplicationID?.characters.count ?? 0))))!
    if numberOfMatches == 0 {
      let message: String = "\"\(prefApplicationID)\" is not a valid application ID\n" +
      "Please fix the app settings (should be 8 hex digits, in CAPS)"
      showAlert(withTitle: "Invalid Receiver Application ID", message: message)
      return nil
    }
    return prefApplicationID!
  }
  // MARK: - NSUserDefaults notification

  func syncWithUserDefaults() {
    var userDefaults = UserDefaults.standard
    // Forcing no logging from the SDK
    // _enableSDKLogging = [userDefaults boolForKey:kPrefEnableSDKLogging];
    enableSDKLogging = false
    var mediaNotificationsEnabled: Bool = userDefaults.bool(forKey: kPrefEnableMediaNotifications)
    GCKLog("notifications ON? %d", mediaNotificationsEnabled)
    if firstUserDefaultsSync || (self.mediaNotificationsEnabled != mediaNotificationsEnabled) {
      self.mediaNotificationsEnabled = mediaNotificationsEnabled
      if useCastContainerViewController {
        var castContainerVC: GCKUICastContainerViewController?
        castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        castContainerVC?.miniMediaControlsItemEnabled = mediaNotificationsEnabled
      }
      else {
        var rootContainerVC: RootContainerViewController?
        rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        rootContainerVC?.isMiniMediaControlsViewEnabled = mediaNotificationsEnabled
      }
    }
    firstUserDefaultsSync = false
  }
  // MARK: - GCKLoggerDelegate

  func logMessage(_ message: String, fromFunction function: String) {
    if enableSDKLogging {
      // Send SDK's log messages directly to the console.
      print("\(function)  \(message)")
    }
  }
  // MARK: - Notifications

  func presentExpandedMediaControls() {
    print("present expanded media controls")
    // Segue directly to the ExpandedViewController.
    var navigationController: UINavigationController?
    if useCastContainerViewController {
      var castContainerVC: GCKUICastContainerViewController?
      castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
      navigationController = (castContainerVC?.contentViewController as? UINavigationController)
    }
    else {
      var rootContainerVC: RootContainerViewController?
      rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      navigationController = rootContainerVC?.navigationController
    }
    navigationController?.navigationItem.backBarButton = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    if (appDelegate?.isCastControlBarsEnabled)! {
      appDelegate?.isCastControlBarsEnabled = false
    }
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }
  // MARK: - GCKSessionManagerListener

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    if error == nil {
      Toast.displayMessage("Session ended", for: 3, in: (window?.rootViewController?.view)!)
    }
    else {
      let message = "Session ended unexpectedly:\n\(error?.localizedDescription)"
      showAlert(withTitle: "Session error", message: message)
    }
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
    let message = "Failed to start session:\n\(error.localizedDescription)"
    showAlert(withTitle: "Session error", message: message)
  }

  func showAlert(withTitle title: String, message: String) {
    let alert = UIAlertView(title: title, message: message, delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
    alert.show()
  }
  // MARK: - GCKUIImagePicker

  func getImageWith(_ imageHints: GCKUIImageHints, from metadata: GCKMediaMetadata) -> GCKImage? {
    if metadata && metadata.images && (metadata.images.count > 0) {
      if metadata.images().count == 1 {
        return metadata.images[0]
      }
      else {
        if imageHints.imageType == GCKMediaMetadataImageTypeBackground {
          return metadata.images[1]
        }
        else {
          return metadata.images[0]
        }
      }
    }
    else {
      print("No images available in media metadata. ")
      return nil
    }
  }
}
