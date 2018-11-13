// Copyright 2018 Google Inc. All Rights Reserved.
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

#import "ActionSheet.h"
#import "MediaViewController.h"

#import <GoogleCast/GoogleCast.h>

#import "MediaItem.h"
#import "MediaListModel.h"

#import "AppDelegate.h"
#import "LocalPlayerView.h"
#import "Toast.h"

/* The player state. */
typedef NS_ENUM(NSInteger, PlaybackMode) {
  PlaybackModeNone = 0,
  PlaybackModeLocal,
  PlaybackModeRemote
};

static NSString *const kPrefShowStreamTimeRemaining =
    @"show_stream_time_remaining";

@interface MediaViewController ()<GCKSessionManagerListener,
                                  GCKRemoteMediaClientListener,
                                  LocalPlayerViewDelegate, GCKRequestDelegate> {
  IBOutlet UILabel *_titleLabel;
  IBOutlet UILabel *_subtitleLabel;
  IBOutlet UITextView *_descriptionTextView;
  IBOutlet LocalPlayerView *_localPlayerView;
  GCKSessionManager *_sessionManager;
  GCKCastSession *_castSession;
  GCKUIMediaController *_castMediaController;
  GCKUIDeviceVolumeController *_volumeController;
  BOOL _streamPositionSliderMoving;
  PlaybackMode _playbackMode;
  UIBarButtonItem *_queueButton;
  BOOL _showStreamTimeRemaining;
  BOOL _localPlaybackImplicitlyPaused;
  ActionSheet *_actionSheet;
  BOOL _queueAdded;
  CAGradientLayer *_gradient;
  GCKUICastButton *_castButton;
}

/* Whether to reset the edges on disappearing. */
@property(nonatomic) BOOL resetEdgesOnDisappear;

@end

@implementation MediaViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:(NSCoder *)coder];
  if (self) {
    _sessionManager = [GCKCastContext sharedInstance].sessionManager;
    _castMediaController = [[GCKUIMediaController alloc] init];
    _volumeController = [[GCKUIDeviceVolumeController alloc] init];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  NSLog(@"in MediaViewController viewDidLoad");

  _localPlayerView.delegate = self;

  _castButton =
      [[GCKUICastButton alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
  _castButton.tintColor = [UIColor whiteColor];
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithCustomView:_castButton];

  _playbackMode = PlaybackModeNone;

  _queueButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage imageNamed:@"playlist_white.png"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(didTapQueueButton:)];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
        selector:@selector(castDeviceDidChange:)
            name:kGCKCastStateDidChangeNotification
          object:[GCKCastContext sharedInstance]];
}

- (void)castDeviceDidChange:(NSNotification *)notification {
  if ([GCKCastContext sharedInstance].castState != GCKCastStateNoDevicesAvailable) {
    // You can present the instructions on how to use Google Cast on
    // the first time the user uses you app
    [[GCKCastContext sharedInstance] presentCastInstructionsViewControllerOnceWithCastButton:_castButton];
  }
}

- (void)viewWillAppear:(BOOL)animated {
  NSLog(@"viewWillAppear; mediaInfo is %@, mode is %d", self.mediaInfo,
        (int)_playbackMode);

  appDelegate.castControlBarsEnabled = YES;

  if ((_playbackMode == PlaybackModeLocal) && _localPlaybackImplicitlyPaused) {
    [_localPlayerView play];
    _localPlaybackImplicitlyPaused = NO;
  }

  // Do we need to switch modes? If we're in remote playback mode but no longer
  // have a session, then switch to local playback mode. If we're in local mode
  // but now have a session, then switch to remote playback mode.
  BOOL hasConnectedSession = (_sessionManager.hasConnectedSession);
  if (hasConnectedSession && (_playbackMode != PlaybackModeRemote)) {
    [self populateMediaInfo:NO playPosition:0];
    [self switchToRemotePlayback];
  } else if ((_sessionManager.currentSession == nil) &&
             (_playbackMode != PlaybackModeLocal)) {
    [self switchToLocalPlayback];
  }

  [_sessionManager addListener:self];

  _gradient = [CAGradientLayer layer];
  _gradient.colors = @[(id)[UIColor clearColor].CGColor,
                      (id)[UIColor colorWithRed:(50 / 255.0)
                                           green:(50 / 255.0)
                                            blue:(50 / 255.0)
                                           alpha:(200 / 255.0)].CGColor];
  _gradient.startPoint = CGPointMake(0, 1);
  _gradient.endPoint = CGPointZero;

  UIInterfaceOrientation orientation =
      [UIApplication sharedApplication].statusBarOrientation;

  if (UIInterfaceOrientationIsLandscape(orientation)) {
    [self setNavigationBarStyle:LPVNavBarTransparent];
  } else if (_resetEdgesOnDisappear) {
    [self setNavigationBarStyle:LPVNavBarDefault];
  }

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(deviceOrientationDidChange:)
             name:UIDeviceOrientationDidChangeNotification
           object:nil];
  [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

  [super viewWillAppear:animated];
}

- (void)setQueueButtonVisible:(BOOL)visible {
  if (visible && !_queueAdded) {
    NSMutableArray *barItems = [[NSMutableArray alloc]
        initWithArray:self.navigationItem.rightBarButtonItems];
    [barItems addObject:_queueButton];
    self.navigationItem.rightBarButtonItems = barItems;
    _queueAdded = YES;
  } else if (!visible && _queueAdded) {
    NSMutableArray *barItems = [[NSMutableArray alloc]
        initWithArray:self.navigationItem.rightBarButtonItems];
    [barItems removeObject:_queueButton];
    self.navigationItem.rightBarButtonItems = barItems;
    _queueAdded = NO;
  }
}

- (void)viewWillDisappear:(BOOL)animated {
  NSLog(@"viewWillDisappear");
  [self setNavigationBarStyle:LPVNavBarDefault];
  switch (_playbackMode) {
    case PlaybackModeLocal:
      if (_localPlayerView.playerState == LocalPlayerStatePlaying ||
          _localPlayerView.playerState == LocalPlayerStateStarting) {
        _localPlaybackImplicitlyPaused = YES;
        [_localPlayerView pause];
      }
      break;
    case PlaybackModeRemote:
    case PlaybackModeNone:
    default:
      // Do nothing.
      break;
  }

  [_sessionManager removeListener:self];

  [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:UIDeviceOrientationDidChangeNotification
              object:nil];

  [super viewWillDisappear:animated];
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
  NSLog(@"Orientation changed.");
  UIInterfaceOrientation orientation =
      [UIApplication sharedApplication].statusBarOrientation;
  if (UIInterfaceOrientationIsLandscape(orientation)) {
    [self setNavigationBarStyle:LPVNavBarTransparent];
  } else if (!UIInterfaceOrientationIsLandscape(orientation) ||
             !_localPlayerView.playingLocally) {
    [self setNavigationBarStyle:LPVNavBarDefault];
  }

  [_localPlayerView orientationChanged];
}

- (void)setMediaInfo:(GCKMediaInformation *)mediaInfo {
  NSLog(@"setMediaInfo");
  if (mediaInfo) {
    _mediaInfo = mediaInfo;
  }
}

- (void)didTapQueueButton:(id)sender {
  appDelegate.castControlBarsEnabled = NO;
  [self performSegueWithIdentifier:@"MediaQueueSegue" sender:self];
}

#pragma mark - Mode switching

- (void)switchToLocalPlayback {
  NSLog(@"switchToLocalPlayback");

  if (_playbackMode == PlaybackModeLocal) {
    return;
  }

  [self setQueueButtonVisible:NO];

  NSTimeInterval playPosition = 0;
  BOOL paused = NO;
  BOOL ended = NO;
  if (_playbackMode == PlaybackModeRemote) {
    playPosition = _castMediaController.lastKnownStreamPosition;
    paused = (_castMediaController.lastKnownPlayerState ==
              GCKMediaPlayerStatePaused);
    ended =
        (_castMediaController.lastKnownPlayerState == GCKMediaPlayerStateIdle);
    NSLog(@"last player state: %ld, ended: %d",
          (long)_castMediaController.lastKnownPlayerState, ended);
  }

  [self populateMediaInfo:(!paused && !ended) playPosition:playPosition];

  [_castSession.remoteMediaClient removeListener:self];
  _castSession = nil;

  _playbackMode = PlaybackModeLocal;
}

- (void)populateMediaInfo:(BOOL)autoPlay
             playPosition:(NSTimeInterval)playPosition {
  NSLog(@"populateMediaInfo");
  _titleLabel.text =
      [self.mediaInfo.metadata stringForKey:kGCKMetadataKeyTitle];

  NSString *subtitle =
      [self.mediaInfo.metadata stringForKey:kGCKMetadataKeyArtist];
  if (!subtitle) {
    subtitle = [self.mediaInfo.metadata stringForKey:kGCKMetadataKeyStudio];
  }
  _subtitleLabel.text = subtitle;

  NSString *description =
      [self.mediaInfo.metadata stringForKey:kMediaKeyDescription];
  _descriptionTextView.text =
      [description stringByReplacingOccurrencesOfString:@"\\n"
                                             withString:@"\n"];
  [_localPlayerView loadMedia:self.mediaInfo
                     autoPlay:autoPlay
                 playPosition:playPosition];
}

- (void)switchToRemotePlayback {
  NSLog(@"switchToRemotePlayback; mediaInfo is %@", self.mediaInfo);

  if (_playbackMode == PlaybackModeRemote) {
    return;
  }

  if ([_sessionManager.currentSession isKindOfClass:[GCKCastSession class]]) {
    _castSession = (GCKCastSession *)_sessionManager.currentSession;
  }

  // If we were playing locally, load the local media on the remote player
  if ((_playbackMode == PlaybackModeLocal) &&
      (_localPlayerView.playerState != LocalPlayerStateStopped) &&
      self.mediaInfo) {
    NSLog(@"loading media: %@", self.mediaInfo);
    NSTimeInterval playPosition = _localPlayerView.streamPosition;
    BOOL paused = (_localPlayerView.playerState == LocalPlayerStatePaused);
    GCKMediaQueueItemBuilder *builder = [[GCKMediaQueueItemBuilder alloc] init];
    builder.mediaInformation = self.mediaInfo;
    builder.autoplay = !paused;
    builder.preloadTime =
        [[NSUserDefaults standardUserDefaults] integerForKey:kPrefPreloadTime];
    GCKMediaQueueItem *item = [builder build];

    [_castSession.remoteMediaClient queueLoadItems:@[ item ]
                                        startIndex:0
                                      playPosition:playPosition
                                        repeatMode:GCKMediaRepeatModeOff
                                        customData:nil];
  }
  [_localPlayerView stop];
  [_localPlayerView showSplashScreen];
  [self setQueueButtonVisible:YES];
  [_castSession.remoteMediaClient addListener:self];
  _playbackMode = PlaybackModeRemote;
}

- (void)clearMetadata {
  _titleLabel.text = @"";
  _subtitleLabel.text = @"";
  _descriptionTextView.text = @"";
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil];
  [alert show];
}

#pragma mark - Local playback UI actions

- (void)startAdjustingStreamPosition:(id)sender {
  _streamPositionSliderMoving = YES;
}

- (void)finishAdjustingStreamPosition:(id)sender {
  _streamPositionSliderMoving = NO;
}

- (void)togglePlayPause:(id)sender {
  [_localPlayerView togglePause];
}

#pragma mark - GCKSessionManagerListener

- (void)sessionManager:(GCKSessionManager *)sessionManager
       didStartSession:(GCKSession *)session {
  NSLog(@"MediaViewController: sessionManager didStartSession %@", session);
  [self setQueueButtonVisible:YES];
  [self switchToRemotePlayback];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
      didResumeSession:(GCKSession *)session {
  NSLog(@"MediaViewController: sessionManager didResumeSession %@", session);
  [self setQueueButtonVisible:YES];
  [self switchToRemotePlayback];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
         didEndSession:(GCKSession *)session
             withError:(NSError *)error {
  NSLog(@"session ended with error: %@", error);
  NSString *message =
      [NSString stringWithFormat:@"The Casting session has ended.\n%@",
                                 error.description];

  [Toast displayToastMessage:message
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:NO];
  [self switchToLocalPlayback];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didFailToStartSessionWithError:(NSError *)error {
  [self showAlertWithTitle:@"Failed to start a session"
                   message:error.description];
  [self setQueueButtonVisible:NO];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
didFailToResumeSession:(GCKSession *)session
             withError:(NSError *)error {
  [Toast displayToastMessage:@"The Casting session could not be resumed."
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:NO];
  [self switchToLocalPlayback];
}

#pragma mark - GCKRemoteMediaClientListener

- (void)remoteMediaClient:(GCKRemoteMediaClient *)player
     didUpdateMediaStatus:(GCKMediaStatus *)mediaStatus {
  self.mediaInfo = mediaStatus.mediaInformation;
}

#pragma mark - LocalPlayerViewDelegate

/* Signal the requested style for the view. */
- (void)setNavigationBarStyle:(LPVNavBarStyle)style {
  if (style == LPVNavBarDefault) {
    NSLog(@"setNavigationBarStyle: Default");
  } else if (style == LPVNavBarTransparent) {
    NSLog(@"setNavigationBarStyle: Transparent");
  } else {
    NSLog(@"setNavigationBarStyle: Unknown - %ld", (unsigned long)style);
  }

  if (style == LPVNavBarDefault) {
    self.edgesForExtendedLayout = UIRectEdgeAll;
    [self hideNavigationBar:NO];
    [self.navigationController.navigationBar setTranslucent:NO];
    [self.navigationController.navigationBar
        setBackgroundImage:nil
             forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = nil;
    [[UIApplication sharedApplication]
        setStatusBarHidden:NO
             withAnimation:UIStatusBarAnimationFade];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    _resetEdgesOnDisappear = NO;
  } else if (style == LPVNavBarTransparent) {
    self.edgesForExtendedLayout = UIRectEdgeTop;
    [self.navigationController.navigationBar setTranslucent:YES];

    // Gradient background
    _gradient.frame = self.navigationController.navigationBar.bounds;
    UIGraphicsBeginImageContext(_gradient.bounds.size);
    [_gradient renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *gradientImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [self.navigationController.navigationBar setBackgroundImage:gradientImage
                                                  forBarMetrics:UIBarMetricsDefault];

    self.navigationController.navigationBar.shadowImage = [UIImage new];
    [[UIApplication sharedApplication]
        setStatusBarHidden:YES
             withAnimation:UIStatusBarAnimationFade];
    // Disable the swipe gesture if we're fullscreen.
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    _resetEdgesOnDisappear = YES;
  }
}

/* Request the navigation bar to be hidden or shown. */
- (void)hideNavigationBar:(BOOL)hide {
  if (hide) {
    NSLog(@"HIDE NavBar.");
  } else {
    NSLog(@"SHOW NavBar.");
  }
  (self.navigationController.navigationBar).hidden = hide;
}

/* Play has been pressed in the LocalPlayerView. */
- (BOOL)continueAfterPlayButtonClicked {
  BOOL hasConnectedCastSession =
      [GCKCastContext sharedInstance].sessionManager.hasConnectedCastSession;
  if (self.mediaInfo && hasConnectedCastSession) {
    // Display an alert box to allow the user to add to queue or play
    // immediately.
    if (!_actionSheet) {
      _actionSheet = [[ActionSheet alloc] initWithTitle:@"Play Item"
                                                message:@"Select an action"
                                       cancelButtonText:@"Cancel"];
      [_actionSheet addActionWithTitle:@"Play Now"
                                target:self
                              selector:@selector(playSelectedItemRemotely)];
      [_actionSheet addActionWithTitle:@"Add to Queue"
                                target:self
                              selector:@selector(enqueueSelectedItemRemotely)];
    }
    [_actionSheet presentInController:self sourceView:_localPlayerView];
    return NO;
  }

  return YES;
}

- (void)playSelectedItemRemotely {
  [self loadSelectedItemByAppending:NO];
  [[GCKCastContext sharedInstance] presentDefaultExpandedMediaControls];
}

- (void)enqueueSelectedItemRemotely {
  [self loadSelectedItemByAppending:YES];
  NSString *message =
      [NSString stringWithFormat:@"Added \"%@\" to queue.",
                                 [self.mediaInfo.metadata
                                     stringForKey:kGCKMetadataKeyTitle]];
  [Toast displayToastMessage:message
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:YES];
}

/**
 * Loads the currently selected item in the current cast media session.
 * @param appending If YES, the item is appended to the current queue if there
 * is one. If NO, or if
 * there is no queue, a new queue containing only the selected item is created.
 */
- (void)loadSelectedItemByAppending:(BOOL)appending {
  NSLog(@"enqueue item %@", self.mediaInfo);

  GCKSession *session =
      [GCKCastContext sharedInstance].sessionManager.currentSession;
  if ([session isKindOfClass:[GCKCastSession class]]) {
    GCKCastSession *castSession = (GCKCastSession *)session;
    if (castSession.remoteMediaClient) {
      GCKMediaQueueItemBuilder *builder =
          [[GCKMediaQueueItemBuilder alloc] init];
      builder.mediaInformation = self.mediaInfo;
      builder.autoplay = YES;
      builder.preloadTime = [[NSUserDefaults standardUserDefaults]
          integerForKey:kPrefPreloadTime];
      GCKMediaQueueItem *item = [builder build];
      if (castSession.remoteMediaClient.mediaStatus && appending) {
        GCKRequest *request = [castSession.remoteMediaClient
             queueInsertItem:item
            beforeItemWithID:kGCKMediaQueueInvalidItemID];
        request.delegate = self;
      } else {
        GCKMediaRepeatMode repeatMode =
            castSession.remoteMediaClient.mediaStatus
                ? castSession.remoteMediaClient.mediaStatus.queueRepeatMode
                : GCKMediaRepeatModeOff;

        GCKRequest *request =
            [castSession.remoteMediaClient queueLoadItems:@[ item ]
                                               startIndex:0
                                             playPosition:0
                                               repeatMode:repeatMode
                                               customData:nil];
        request.delegate = self;
      }
    }
  }
}

#pragma mark - GCKRequestDelegate

- (void)requestDidComplete:(GCKRequest *)request {
  NSLog(@"request %ld completed", (long)request.requestID);
}

- (void)request:(GCKRequest *)request didFailWithError:(GCKError *)error {
  NSLog(@"request %ld failed with error %@", (long)request.requestID, error);
}

@end
