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

#import "AppDelegate.h"

#import <AVFoundation/AVFoundation.h>
#import <GoogleCast/GoogleCast.h>

#import "MediaViewController.h"
#import "RootContainerViewController.h"
#import "Toast.h"

// You can add your own app id here that you get by registering with the Google Cast SDK
// Developer Console https://cast.google.com/publish or use kGCKDefaultMediaReceiverApplicationID
#define kReceiverAppID @"4F8B3483"

NSString *const kPrefPreloadTime = @"preload_time_sec";

static NSString *const kPrefEnableAnalyticsLogging = @"enable_analytics_logging";
static NSString *const kPrefAppVersion = @"app_version";
static NSString *const kPrefSDKVersion = @"sdk_version";
static NSString *const kPrefEnableMediaNotifications = @"enable_media_notifications";

@interface AppDelegate () <GCKLoggerDelegate, GCKSessionManagerListener, GCKUIImagePicker> {
  BOOL _enableSDKLogging;
  BOOL _mediaNotificationsEnabled;
  BOOL _firstUserDefaultsSync;
  BOOL _useCastContainerViewController;
}
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  _enableSDKLogging = NO;

  [self populateRegistrationDomain];

  // Set your receiver application ID or use
  // kGCKDefaultMediaReceiverApplicationID.
  NSString *applicationID = kReceiverAppID;

  // We are forcing a custom container view controller, but the Cast Container
  // is also available.
  _useCastContainerViewController = NO;

  // Set your receiver application ID.
  GCKDiscoveryCriteria *discoveryCriteria =
      [[GCKDiscoveryCriteria alloc] initWithApplicationID:applicationID];
  GCKCastOptions *options = [[GCKCastOptions alloc] initWithDiscoveryCriteria:discoveryCriteria];
  options.physicalVolumeButtonsWillControlDeviceVolume = YES;
  [GCKCastContext setSharedInstanceWithOptions:options];

  [GCKCastContext sharedInstance].useDefaultExpandedMediaControls = YES;

  // Theme the cast button using UIAppearance.
  [GCKUICastButton appearance].tintColor = [UIColor grayColor];

  self.window.clipsToBounds = YES;

  [self setupCastLogging];

  if (_useCastContainerViewController) {
    UIStoryboard *appStoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *navigationController =
        [appStoryboard instantiateViewControllerWithIdentifier:@"MainNavigation"];
    GCKUICastContainerViewController *castContainerVC = [[GCKCastContext sharedInstance]
        createCastContainerControllerForViewController:navigationController];
    castContainerVC.miniMediaControlsItemEnabled = YES;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = castContainerVC;
    [self.window makeKeyAndVisible];
  } else {
    RootContainerViewController *rootContainerVC =
        (RootContainerViewController *)self.window.rootViewController;
    rootContainerVC.miniMediaControlsViewEnabled = YES;
  }

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(syncWithUserDefaults)
                                               name:NSUserDefaultsDidChangeNotification
                                             object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(presentExpandedMediaControls)
                                               name:kGCKExpandedMediaControlsTriggeredNotification
                                             object:nil];

  _firstUserDefaultsSync = YES;
  [self syncWithUserDefaults];

  [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;

  [[GCKCastContext sharedInstance].sessionManager addListener:self];
  [GCKCastContext sharedInstance].imagePicker = self;

  return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:kGCKExpandedMediaControlsTriggeredNotification
              object:nil];
}

- (void)setupCastLogging {
  GCKLoggerFilter *logFilter = [[GCKLoggerFilter alloc] init];
  [logFilter setLoggingLevel:GCKLoggerLevelVerbose
                  forClasses:@[
                    @"GCKDeviceScanner", @"GCKDeviceProvider", @"GCKDiscoveryManager",
                    @"GCKCastChannel", @"GCKMediaControlChannel", @"GCKUICastButton",
                    @"GCKUIMediaController", @"NSMutableDictionary"
                  ]];
  [GCKLogger sharedInstance].filter = logFilter;
  [GCKLogger sharedInstance].delegate = self;
}

- (void)presentExpandedMediaControls {
  NSLog(@"present expanded media controls");
  // Segue directly to the ExpandedViewController.
  UINavigationController *navigationController;
  if (_useCastContainerViewController) {
    GCKUICastContainerViewController *castContainerVC;
    castContainerVC = (GCKUICastContainerViewController *)self.window.rootViewController;
    navigationController = (UINavigationController *)castContainerVC.contentViewController;
  } else {
    RootContainerViewController *rootContainerVC;
    rootContainerVC = (RootContainerViewController *)self.window.rootViewController;
    navigationController = rootContainerVC.navigationController;
  }

  if (appDelegate.castControlBarsEnabled) {
    appDelegate.castControlBarsEnabled = NO;
  }
  [[GCKCastContext sharedInstance] presentDefaultExpandedMediaControls];
}

#pragma mark - Working with default values

- (void)populateRegistrationDomain {
  NSURL *settingsBundleURL = [[NSBundle mainBundle] URLForResource:@"Settings"
                                                     withExtension:@"bundle"];
  NSString *appVersion =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

  NSMutableDictionary *appDefaults = [NSMutableDictionary dictionary];
  [self loadDefaults:appDefaults fromSettingsPage:@"Root" inSettingsBundleAtURL:settingsBundleURL];
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  [userDefaults registerDefaults:appDefaults];
  [userDefaults setValue:appVersion forKey:kPrefAppVersion];
  [userDefaults setValue:kGCKFrameworkVersion forKey:kPrefSDKVersion];
  [userDefaults synchronize];
}

- (void)loadDefaults:(NSMutableDictionary *)appDefaults
         fromSettingsPage:(NSString *)plistName
    inSettingsBundleAtURL:(NSURL *)settingsBundleURL {
  NSString *plistFileName = [plistName stringByAppendingPathExtension:@"plist"];
  NSDictionary *settingsDict = [NSDictionary
      dictionaryWithContentsOfURL:[settingsBundleURL URLByAppendingPathComponent:plistFileName]];
  NSArray *prefSpecifierArray = settingsDict[@"PreferenceSpecifiers"];

  for (NSDictionary *prefItem in prefSpecifierArray) {
    NSString *prefItemType = prefItem[@"Type"];
    NSString *prefItemKey = prefItem[@"Key"];
    NSString *prefItemDefaultValue = prefItem[@"DefaultValue"];

    if ([prefItemType isEqualToString:@"PSChildPaneSpecifier"]) {
      NSString *prefItemFile = prefItem[@"File"];
      [self loadDefaults:appDefaults
               fromSettingsPage:prefItemFile
          inSettingsBundleAtURL:settingsBundleURL];
    } else if (prefItemKey && prefItemDefaultValue) {
      appDefaults[prefItemKey] = prefItemDefaultValue;
    }
  }
}

#pragma mark - NSUserDefaults notification

- (void)syncWithUserDefaults {
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

  BOOL mediaNotificationsEnabled = [userDefaults boolForKey:kPrefEnableMediaNotifications];
  GCKLog(@"notifications ON? %d", mediaNotificationsEnabled);

  if (_firstUserDefaultsSync || (_mediaNotificationsEnabled != mediaNotificationsEnabled)) {
    _mediaNotificationsEnabled = mediaNotificationsEnabled;
    if (_useCastContainerViewController) {
      GCKUICastContainerViewController *castContainerVC;
      castContainerVC = (GCKUICastContainerViewController *)self.window.rootViewController;
      castContainerVC.miniMediaControlsItemEnabled = _mediaNotificationsEnabled;
    } else {
      RootContainerViewController *rootContainerVC;
      rootContainerVC = (RootContainerViewController *)self.window.rootViewController;
      rootContainerVC.miniMediaControlsViewEnabled = _mediaNotificationsEnabled;
    }
  }

  _firstUserDefaultsSync = NO;
}

#pragma mark - GCKLoggerDelegate

- (void)logMessage:(NSString *)message
           atLevel:(GCKLoggerLevel)level
      fromFunction:(NSString *)function
          location:(NSString *)location {
  if (_enableSDKLogging) {
    // Send SDK's log messages directly to the console.
    NSLog(@"%@: %@ - %@", location, function, message);
  }
}

#pragma mark - Notifications

- (void)setCastControlBarsEnabled:(BOOL)notificationsEnabled {
  if (_useCastContainerViewController) {
    GCKUICastContainerViewController *castContainerVC;
    castContainerVC = (GCKUICastContainerViewController *)self.window.rootViewController;
    castContainerVC.miniMediaControlsItemEnabled = notificationsEnabled;
  } else {
    RootContainerViewController *rootContainerVC;
    rootContainerVC = (RootContainerViewController *)self.window.rootViewController;
    rootContainerVC.miniMediaControlsViewEnabled = notificationsEnabled;
  }
}

- (BOOL)castControlBarsEnabled {
  if (_useCastContainerViewController) {
    GCKUICastContainerViewController *castContainerVC;
    castContainerVC = (GCKUICastContainerViewController *)self.window.rootViewController;
    return castContainerVC.miniMediaControlsItemEnabled;
  } else {
    RootContainerViewController *rootContainerVC;
    rootContainerVC = (RootContainerViewController *)self.window.rootViewController;
    return rootContainerVC.miniMediaControlsViewEnabled;
  }
}

#pragma mark - GCKSessionManagerListener

- (void)sessionManager:(GCKSessionManager *)sessionManager
         didEndSession:(GCKSession *)session
             withError:(NSError *)error {
  if (!error) {
    [Toast displayToastMessage:@"Session ended"
               forTimeInterval:3
                        inView:self.window.rootViewController.view];
  } else {
    NSString *message =
        [NSString stringWithFormat:@"Session ended unexpectedly:\n%@", error.localizedDescription];
    [self showAlertWithTitle:@"Session error" message:message];
  }
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didFailToStartSession:(GCKSession *)session
                withError:(NSError *)error {
  NSString *message =
      [NSString stringWithFormat:@"Failed to start session:\n%@", error.localizedDescription];
  [self showAlertWithTitle:@"Session error" message:message];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:title
                                          message:message
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Ok"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
  [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - GCKUIImagePicker

- (GCKImage *)getImageWithHints:(GCKUIImageHints *)imageHints
                   fromMetadata:(GCKMediaMetadata *)metadata {
  if (metadata && metadata.images && ((metadata.images).count > 0)) {
    if ((metadata.images).count == 1) {
      return (metadata.images)[0];
    } else {
      if (imageHints.imageType == GCKMediaMetadataImageTypeBackground) {
        return (metadata.images)[1];
      } else {
        return (metadata.images)[0];
      }
    }
  } else {
    NSLog(@"No images available in media metadata. ");
    return nil;
  }
}

@end
