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

let kApplicationID: String = ""

let kPrefPreloadTime: String = ""

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GCKLoggerDelegate, GCKSessionManagerListener, GCKUIImagePicker {
  var enableSDKLogging = false
  var mediaNotificationsEnabled = false
  var firstUserDefaultsSync = false
  var useCastContainerViewController = false

  var window: UIWindow!
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
          return rootContainerVC.miniMediaControlsViewEnabled
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
        rootContainerVC?.miniMediaControlsViewEnabled = notificationsEnabled
      }
    }
  }


  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    populateRegistrationDomain()
    var applicationID: String = applicationIDFromUserDefaults()
    if applicationID == "" {
      // Don't try to go on without a valid application ID - SDK will fail an
      // assert and app will crash.
      return true
    }
    // We are forcing a custom container view controller, but the Cast Container
    // is also available
    useCastContainerViewController = false
    var options = GCKCastOptions(receiverApplicationID: applicationID)
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
    window?.clipsToBounds = true
    var logFilter = GCKLoggerFilter()
    logFilter.exclusive = true
    logFilter.addClassNames(["GCKDeviceScanner", "GCKDeviceProvider", "GCKDiscoveryManager", "GCKCastChannel", "GCKMediaControlChannel", "GCKUICastButton", "GCKUIMediaController", "NSMutableDictionary"])
    GCKLogger.sharedInstance().filter = logFilter
    GCKLogger.sharedInstance().delegate = self
    // Set playback category mode to allow playing audio on the video files even
    // when the ringer mute switch is on.
    var setCategoryError: Error?
    var success: Bool? = try? AVAudioSession.sharedInstance().setCategory(.playback)
    if success == nil {
      print("Error setting audio category: \(setCategoryError?.localizedDescription)")
    }
    NotificationCenter.default.addObserver(self, selector: #selector(syncWithUserDefaults), name: UserDefaults.didChangeNotification, object: nil)
    if useCastContainerViewController {
      var appStoryboard = UIStoryboard(name: "Main", bundle: nil)
      var navigationController: UINavigationController? = appStoryboard.instantiateViewController(withIdentifier: "MainNavigation")
      var castContainerVC: GCKUICastContainerViewController?
      castContainerVC = GCKCastContext.sharedInstance().createCastContainerController(forViewController: navigationController)
      castContainerVC?.miniMediaControlsItemEnabled = true
      window = UIWindow(frame: UIScreen.main.bounds)
      window?.rootViewController = castContainerVC
      window?.makeKeyAndVisible()
    }
    else {
      var rootContainerVC: RootContainerViewController?
      rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      rootContainerVC?.miniMediaControlsViewEnabled = true
    }
    NotificationCenter.default.addObserver(self, selector: #selector(presentExpandedMediaControls), name: kGCKExpandedMediaControlsTriggeredNotification, object: nil)
    firstUserDefaultsSync = true
    syncWithUserDefaults()
    UIApplication.shared.statusBarStyle = UIStatusBarStyleLightContent
    GCKCastContext.sharedInstance().sessionManager.addListener(self)
    GCKCastContext.sharedInstance().imagePicker = self
    return true
  }

  func applicationWillTerminate(_ application: UIApplication) {
    NotificationCenter.default.removeObserver(self, name: kGCKExpandedMediaControlsTriggeredNotification, object: nil)
  }

  func populateRegistrationDomain() {
    var settingsBundleURL: URL? = Bundle.main.url(forResource: "Settings", withExtension: "bundle")
    var appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    var appDefaults = [AnyHashable: Any]()
    loadDefaults(appDefaults, fromSettingsPage: "Root", inSettingsBundleAt: settingsBundleURL)
    var userDefaults = UserDefaults.standard
    userDefaults.register(defaults: appDefaults)
    userDefaults.setValue(appVersion, forKey: kPrefAppVersion)
    userDefaults.setValue(kGCKFrameworkVersion, forKey: kPrefSDKVersion)
    userDefaults.synchronize()
  }

  func loadDefaults(_ appDefaults: [AnyHashable: Any], fromSettingsPage plistName: String, inSettingsBundleAt settingsBundleURL: URL) {
    var plistFileName: String? = plistName.appendingPathExtension("plist")
    var settingsDict = [AnyHashable: Any](contentsOfURL: settingsBundleURL.appendingPathComponent(plistFileName))
    var prefSpecifierArray: [Any]? = (settingsDict["PreferenceSpecifiers"] as? String)
    for prefItem: [AnyHashable: Any] in prefSpecifierArray {
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

  func applicationIDFromUserDefaults() -> String {
    var userDefaults = UserDefaults.standard
    var prefApplicationID: String? = userDefaults.string(forKey: kPrefReceiverAppID)
    if (prefApplicationID == kPrefCustomReceiverSelectedValue) {
      prefApplicationID = userDefaults.string(forKey: kPrefCustomReceiverAppID)
    }
    var appIdRegex = try? NSRegularExpression(pattern: "\\b[0-9A-F]{8}\\b", options: [])
    var numberOfMatches: Int = appIdRegex?.numberOfMatches(in: prefApplicationID, options: [], range: NSRange(location: 0, length: (prefApplicationID?.characters.count ?? 0)))
    if numberOfMatches == 0 {
      var message: String = "\"\(prefApplicationID)\" is not a valid application ID\n" +
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
    if firstUserDefaultsSync || (mediaNotificationsEnabled != mediaNotificationsEnabled) {
      mediaNotificationsEnabled = mediaNotificationsEnabled
      if useCastContainerViewController {
        var castContainerVC: GCKUICastContainerViewController?
        castContainerVC = (window?.rootViewController as? GCKUICastContainerViewController)
        castContainerVC?.miniMediaControlsItemEnabled = mediaNotificationsEnabled
      }
      else {
        var rootContainerVC: RootContainerViewController?
        rootContainerVC = (window?.rootViewController as? RootContainerViewController)
        rootContainerVC?.miniMediaControlsViewEnabled = mediaNotificationsEnabled
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
      navigationController = (castContainerVC?.contentView as? UINavigationController)
    }
    else {
      var rootContainerVC: RootContainerViewController?
      rootContainerVC = (window?.rootViewController as? RootContainerViewController)
      navigationController = rootContainerVC?.navigationController
    }
    navigationController?.navigationItem?.backBarButton = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    if appDelegate.isCastControlBarsEnabled {
      appDelegate.isCastControlBarsEnabled = false
    }
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }
  // MARK: - GCKSessionManagerListener

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    if error == nil {
      Toast.displayMessage("Session ended", forTimeInterval: 3, in: window?.rootViewController?.view)
    }
    else {
      var message: String? = "Session ended unexpectedly:\n\(error?.localizedDescription)"
      showAlert(withTitle: "Session error", message: message)
    }
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error?) {
    var message: String? = "Failed to start session:\n\(error?.localizedDescription)"
    showAlert(withTitle: "Session error", message: message)
  }

  func showAlert(withTitle title: String, message: String) {
    var alert = UIAlertView(title: title, message: message, delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
    alert.show()
  }
  // MARK: - GCKUIImagePicker

  func getImageWith(_ imageHints: GCKUIImageHints, from metadata: GCKMediaMetadata) -> GCKImage {
    if metadata && metadata.images && (metadata.images.count > 0) {
      if metadata.images.count == 1 {
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
let appDelegate = (UIApplication.shared.delegate as? AppDelegate)
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
// Copyright 2015 Google Inc. All Rights Reserved.
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
