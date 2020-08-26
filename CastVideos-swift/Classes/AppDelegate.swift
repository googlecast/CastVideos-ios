// Copyright 2019 Google LLC. All Rights Reserved.
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

import AVFoundation
import GoogleCast
import UIKit

let kPrefPreloadTime = "preload_time_sec"
let kPrefEnableAnalyticsLogging = "enable_analytics_logging"
let kPrefAppVersion = "app_version"
let kPrefSDKVersion = "sdk_version"
let kPrefEnableMediaNotifications = "enable_media_notifications"

let appDelegate = (UIApplication.shared.delegate as? AppDelegate)

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  // You can add your own app id here that you get by registering with the Google Cast SDK
  // Developer Console https://cast.google.com/publish or use kGCKDefaultMediaReceiverApplicationID
  let kReceiverAppID = "C0868879"
  fileprivate var enableSDKLogging = false
  fileprivate var mediaNotificationsEnabled = false
  fileprivate var firstUserDefaultsSync = false
  fileprivate var useCastContainerViewController = false

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

  func application(_: UIApplication,
                   didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    populateRegistrationDomain()

    // We are forcing a custom container view controller, but the Cast Container is also available.
    useCastContainerViewController = false

    // Set your receiver application ID.
    let options = GCKCastOptions(discoveryCriteria: GCKDiscoveryCriteria(applicationID: kReceiverAppID))
    options.physicalVolumeButtonsWillControlDeviceVolume = true
    
    /** Following code enables CastConnect */
     let launchOptions = GCKLaunchOptions()
     launchOptions.androidReceiverCompatible = true
     options.launchOptions = launchOptions
    
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true

    // Theme the cast button using UIAppearance.
    GCKUICastButton.appearance().tintColor = UIColor.gray

    window?.clipsToBounds = true
    setupCastLogging()

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
                                           name: UserDefaults.didChangeNotification,
                                           object: nil)
    firstUserDefaultsSync = true
    syncWithUserDefaults()
    UIApplication.shared.statusBarStyle = .lightContent
    GCKCastContext.sharedInstance().sessionManager.add(self)
    GCKCastContext.sharedInstance().imagePicker = self
    return true
  }

  func applicationWillTerminate(_: UIApplication) {
    NotificationCenter.default.removeObserver(self,
                                              name: NSNotification.Name.gckExpandedMediaControlsTriggered,
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
}

// MARK: - Working with default values

extension AppDelegate {
  func populateRegistrationDomain() {
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    var appDefaults = [String: Any]()
    if let settingsBundleURL = Bundle.main.url(forResource: "Settings", withExtension: "bundle") {
      loadDefaults(&appDefaults, fromSettingsPage: "Root", inSettingsBundleAt: settingsBundleURL)
    }
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
    if let prefSpecifierArray = settingsDict?["PreferenceSpecifiers"] as? [[AnyHashable: Any]] {
      for prefItem in prefSpecifierArray {
        let prefItemType = prefItem["Type"] as? String
        let prefItemKey = prefItem["Key"] as? String
        let prefItemDefaultValue = prefItem["DefaultValue"] as? String
        if prefItemType == "PSChildPaneSpecifier" {
          if let prefItemFile = prefItem["File"] as? String {
            loadDefaults(&appDefaults, fromSettingsPage: prefItemFile, inSettingsBundleAt: settingsBundleURL)
          }
        } else if let prefItemKey = prefItemKey, let prefItemDefaultValue = prefItemDefaultValue {
          appDefaults[prefItemKey] = prefItemDefaultValue
        }
      }
    }
  }

  @objc func syncWithUserDefaults() {
    let userDefaults = UserDefaults.standard

    let mediaNotificationsEnabled = userDefaults.bool(forKey: kPrefEnableMediaNotifications)
    GCKLogger.sharedInstance().delegate?.logMessage?("Notifications on? \(mediaNotificationsEnabled)", at: .debug, fromFunction: #function, location: "AppDelegate.swift")

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
  func logMessage(_ message: String,
                  at _: GCKLoggerLevel,
                  fromFunction function: String,
                  location: String) {
    if enableSDKLogging {
      // Send SDK's log messages directly to the console.
      print("\(location): \(function) - \(message)")
    }
  }
}

// MARK: - GCKSessionManagerListener

extension AppDelegate: GCKSessionManagerListener {
  func sessionManager(_: GCKSessionManager, didEnd _: GCKSession, withError error: Error?) {
    if error == nil {
      if let view = window?.rootViewController?.view {
        Toast.displayMessage("Session ended", for: 3, in: view)
      }
    } else {
      let message = "Session ended unexpectedly:\n\(error?.localizedDescription ?? "")"
      showAlert(withTitle: "Session error", message: message)
    }
  }

  func sessionManager(_: GCKSessionManager, didFailToStart _: GCKSession, withError error: Error) {
    let message = "Failed to start session:\n\(error.localizedDescription)"
    showAlert(withTitle: "Session error", message: message)
  }

  func showAlert(withTitle title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Ok", style: .default))
    window?.rootViewController?.present(alert, animated: true, completion: nil)
  }
}

// MARK: - GCKUIImagePicker

extension AppDelegate: GCKUIImagePicker {
  func getImageWith(_ imageHints: GCKUIImageHints, from metadata: GCKMediaMetadata) -> GCKImage? {
    let images = metadata.images
    guard !images().isEmpty else { print("No images available in media metadata."); return nil }
    if images().count > 1, imageHints.imageType == .background {
      return images()[1] as? GCKImage
    } else {
      return images()[0] as? GCKImage
    }
  }
}
