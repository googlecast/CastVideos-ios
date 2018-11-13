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

#import "LocalPlayerView.h"

#import <AVFoundation/AVFoundation.h>
#import <GoogleCast/GoogleCast.h>

/* Time to wait before hiding the toolbar. UX is that this number is effectively
 * doubled. */
static NSInteger kToolbarDelay = 3;
/* The height of the toolbar view. */
static NSInteger kToolbarHeight = 44;

@interface LocalPlayerView () {
  AVPlayer *_mediaPlayer;
  AVPlayerLayer *_mediaPlayerLayer;
  id _mediaTimeObserver;
  BOOL _observingMediaPlayer;
  // If there is a pending request to seek to a new position.
  NSTimeInterval _pendingPlayPosition;
  // If there is a pending request to start playback.
  BOOL _pendingPlay;
  // If a seek is currently in progress.
  BOOL _seeking;
}

@property(nonatomic, assign, readwrite) NSTimeInterval streamPosition;
@property(nonatomic, assign, readwrite) NSTimeInterval streamDuration;
@property(nonatomic, strong, readwrite) GCKMediaInformation *media;
@property(nonatomic, assign, readwrite) LocalPlayerState playerState;

/* The aspect ratio constraint for the view. */
@property(nonatomic, weak) IBOutlet NSLayoutConstraint *viewAspectRatio;
/* The splash image to display before playback or while casting. */
@property UIImageView *splashImage;
/* The UIView used for receiving control input. */
@property(nonatomic) UIView *controlView;
/* The gesture recognizer used to register taps to bring up the controls. */
@property(nonatomic) UIGestureRecognizer *singleFingerTap;
/* Whether there has been a recent touch, for fading controls when playing. */
@property(nonatomic) BOOL recentInteraction;

/* Views dictionary used to the layout management. */
@property(nonatomic) NSDictionary *viewsDictionary;
/* Views dictionary used to the layout management. */
@property(nonatomic) NSArray *constraints;
/* Play/Pause button. */
@property(nonatomic) UIButton *playButton;
/* Splash play button. */
@property(nonatomic) UIButton *splashPlayButton;
/* Playback position slider. */
@property(nonatomic) UISlider *slider;
/* Label displaying length of video. */
@property(nonatomic) UILabel *totalTime;
/* View for containing play controls. */
@property(nonatomic) UIView *toolbarView;
/* Play image. */
@property(nonatomic) UIImage *playImage;
/* Pause image. */
@property(nonatomic) UIImage *pauseImage;
/* Loading indicator */
@property(nonatomic) UIActivityIndicatorView *activityIndicator;

@end

@implementation LocalPlayerView

- (void)dealloc {
  [self purgeMediaPlayer];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout Managment

- (void)layoutSubviews {
  CGRect frame =
      self.fullscreen ? [UIScreen mainScreen].bounds : [self fullFrame];
  if ((NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1) &&
      self.fullscreen) {
    // Below iOS 8 the bounds don't change with orientation changes.
    frame.size = CGSizeMake(frame.size.height, frame.size.width);
  }

  (self.splashImage).frame = frame;
  _mediaPlayerLayer.frame = frame;
  (self.controlView).frame = frame;
  [self layoutToolbar:frame];
  _activityIndicator.center = self.controlView.center;
}

/* Update the frame for the toolbar. */
- (void)layoutToolbar:(CGRect)frame {
  (self.toolbarView).frame = CGRectMake(0, frame.size.height - kToolbarHeight,
                                        frame.size.width, kToolbarHeight);
}

/* Return the full frame with no offsets. */
- (CGRect)fullFrame {
  return CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
}

- (void)updateConstraints {
  [super updateConstraints];
  // Active is iOS 8 only, so only do this if available.
  if ([self.viewAspectRatio respondsToSelector:@selector(setActive:)]) {
    self.viewAspectRatio.active = !self.fullscreen;
  }
}

#pragma mark - Public interface

- (void)loadMedia:(GCKMediaInformation *)media
         autoPlay:(BOOL)autoPlay
     playPosition:(NSTimeInterval)playPosition {
  NSLog(@"loadMedia %d", autoPlay);

  if (media != nil && [self.media.contentID isEqualToString:media.contentID]) {
    // Don't reinit if we already have the media.
    return;
  }

  self.media = media;
  if (media == nil) {
    [self purgeMediaPlayer];
    return;
  }

  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.playerState = LocalPlayerStateStopped;

  _splashImage = [[UIImageView alloc] initWithFrame:[self fullFrame]];
  _splashImage.contentMode = UIViewContentModeScaleAspectFill;
  _splashImage.clipsToBounds = YES;
  [self addSubview:_splashImage];

  // Single-tap control view to bring controls back to the front.
  _controlView = [[UIView alloc] init];
  self.singleFingerTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(didTouchControl:)];
  [_controlView addGestureRecognizer:self.singleFingerTap];
  [self addSubview:_controlView];

  // Play overlay that users can tap to get started.
  UIImage *giantPlayButton = [UIImage imageNamed:@"play_circle"];
  self.splashPlayButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.splashPlayButton.frame = [self fullFrame];
  self.splashPlayButton.contentMode = UIViewContentModeCenter;
  [self.splashPlayButton setImage:giantPlayButton
                         forState:UIControlStateNormal];
  self.splashPlayButton.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.splashPlayButton addTarget:self
                            action:@selector(playButtonClicked:)
                  forControlEvents:UIControlEventTouchUpInside];
  self.splashPlayButton.tintColor = [UIColor whiteColor];
  [self addSubview:self.splashPlayButton];

  _pendingPlayPosition = playPosition;
  _pendingPlay = autoPlay;

  [self initialiseToolbarControls];

  [self loadMediaImage];
  [self configureControls];
}

/* YES if we the local media is playing or paused, NO if casting or on the
 * splash screen. */
- (BOOL)playingLocally {
  return self.playerState == LocalPlayerStatePlaying ||
         self.playerState == LocalPlayerStatePaused;
}

- (void)togglePause {
  switch (self.playerState) {
    case LocalPlayerStatePaused:
      [self play];
      break;

    case LocalPlayerStatePlaying:
      [self pause];
      break;

    default:
      // Do nothing.
      break;
  }
}

- (void)pause {
  if (self.playerState == LocalPlayerStatePlaying) {
    [self playButtonClicked:self];
  }
}

- (void)play {
  if (_seeking) {
    _pendingPlay = YES;
  } else if (self.playerState == LocalPlayerStatePaused) {
    [_mediaPlayer play];
    self.playerState = LocalPlayerStatePlaying;
  } else if (self.playerState == LocalPlayerStateStarting) {
    self.playerState = LocalPlayerStatePlaying;
  }
}

- (void)stop {
  [self purgeMediaPlayer];
  self.playerState = LocalPlayerStateStopped;
}

- (void)seekToTime:(NSTimeInterval)time {
  switch (self.playerState) {
    case LocalPlayerStatePlaying:
      _pendingPlay = YES;
      [self performSeekToTime:time];
      break;
    case LocalPlayerStatePaused:
      _pendingPlay = NO;
      [self performSeekToTime:time];
      break;

    case LocalPlayerStateStarting:
      _pendingPlayPosition = time;
      break;

    default:
      break;
  }
}

#pragma mark -

/* Returns YES if we should be in fullscreen. */
- (BOOL)fullscreen {
  BOOL full = (self.playerState != LocalPlayerStateStopped) &&
              UIInterfaceOrientationIsLandscape(
                  [UIApplication sharedApplication].statusBarOrientation);
  NSLog(@"fullscreen=%d", full);
  return full;
}

/* If the orientation changes, display the controls. */
- (void)orientationChanged {
  if (self.fullscreen) {
    [self setFullscreen];
  }
  [self didTouchControl:nil];
}

- (void)setFullscreen {
  NSLog(@"setFullscreen");
  [_delegate setNavigationBarStyle:LPVNavBarTransparent];
  CGRect screenBounds = [UIScreen mainScreen].bounds;
  if (!CGRectEqualToRect(screenBounds, self.frame)) {
    NSLog(@"hideNavigationBar: set fullscreen");
    self.frame = screenBounds;
  }
}

- (void)showSplashScreen {
  // Treat movie as finished to reset.
  [self handleMediaPlaybackEnded];
}

#pragma mark - Media player management

/* Asynchronously load the splash screen image. */
- (void)loadMediaImage {
  NSArray *images = self.media.metadata.images;
  if (images && images.count > 0) {
    GCKImage *image = images[0];
    [[GCKCastContext sharedInstance]
            .imageCache fetchImageForURL:image.URL
                              completion:^(UIImage *image) {
                                _splashImage.image = image;
                              }];
  }
}

- (void)loadMediaPlayer {
  if (!_mediaPlayer) {
    NSURL *mediaURL = [NSURL URLWithString:self.media.contentID];
    _mediaPlayer = [AVPlayer playerWithURL:mediaURL];
    _mediaPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_mediaPlayer];
    _mediaPlayerLayer.frame = [self fullFrame];
    _mediaPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.layer insertSublayer:_mediaPlayerLayer above:_splashImage.layer];
    [self addMediaPlayerObservers];
  }
}

- (void)purgeMediaPlayer {
  [self removeMediaPlayerObservers];

  [_mediaPlayerLayer removeFromSuperlayer];
  _mediaPlayerLayer = nil;
  _mediaPlayer = nil;

  _pendingPlayPosition = kGCKInvalidTimeInterval;
  _pendingPlay = YES;
  _seeking = NO;
}

- (void)handleMediaPlayerReady {
  NSLog(@"handleMediaPlayerReady %d", _pendingPlay);
  if (CMTIME_IS_INDEFINITE(_mediaPlayer.currentItem.duration)) {
    // Loading has failed, try it again.
    [self purgeMediaPlayer];
    [self loadMediaPlayer];
    return;
  }

  if (!self.streamDuration) {
    self.streamDuration = self.slider.maximumValue =
        CMTimeGetSeconds(_mediaPlayer.currentItem.duration);
    self.slider.minimumValue = 0;
    self.slider.enabled = YES;
    self.totalTime.text = [GCKUIUtils timeIntervalAsString:self.streamDuration];
  }

  if (!isnan(_pendingPlayPosition) && _pendingPlayPosition > 0) {
    NSLog(@"seeking to pending position %f", _pendingPlayPosition);
    [self performSeekToTime:_pendingPlayPosition];
    _pendingPlayPosition = kGCKInvalidTimeInterval;
    return;
  } else {
    [_activityIndicator stopAnimating];
  }

  if (_pendingPlay) {
    _pendingPlay = NO;
    [_mediaPlayer play];
    self.playerState = LocalPlayerStatePlaying;
  } else {
    self.playerState = LocalPlayerStatePaused;
  }
}

- (void)performSeekToTime:(NSTimeInterval)time {
  NSLog(@"performSeekToTime");
  [_activityIndicator startAnimating];
  _seeking = YES;
  __block __weak LocalPlayerView *weakSelf = self;
  [_mediaPlayer seekToTime:CMTimeMakeWithSeconds(time, 1)
         completionHandler:^(BOOL finished) {
           LocalPlayerView *strongSelf = weakSelf;
           if (strongSelf) {
             if (strongSelf.playerState == LocalPlayerStateStarting) {
               _pendingPlay = YES;
             }
             [strongSelf handleSeekFinished];
           }
         }];
}

- (void)handleSeekFinished {
  NSLog(@"handleSeekFinished %d", _pendingPlay);
  [_activityIndicator stopAnimating];

  if (_pendingPlay) {
    _pendingPlay = NO;
    [_mediaPlayer play];
    self.playerState = LocalPlayerStatePlaying;
  } else {
    self.playerState = LocalPlayerStatePaused;
  }
  _seeking = NO;
}

/* Callback registered for when the AVPlayer completes playing of the media. */
- (void)handleMediaPlaybackEnded {
  self.playerState = LocalPlayerStateStopped;

  self.streamDuration = 0;
  self.streamPosition = 0;
  self.slider.value = 0;

  [self purgeMediaPlayer];
  [_delegate setNavigationBarStyle:LPVNavBarDefault];
  [_mediaPlayer seekToTime:CMTimeMake(0, 1)];
  [self configureControls];
}

- (void)notifyStreamPositionChanged:(CMTime)time {
  if ((_mediaPlayer.currentItem.status != AVPlayerItemStatusReadyToPlay) ||
      _seeking) {
    return;
  }

  self.streamPosition = (NSTimeInterval)CMTimeGetSeconds(time);
  self.slider.value = self.streamPosition;

  NSTimeInterval remainingTime =
      (self.streamDuration > self.streamPosition)
          ? (self.streamDuration - self.streamPosition)
          : 0;
  if (remainingTime > 0) {
    remainingTime = -remainingTime;
  }
  self.totalTime.text = [GCKUIUtils timeIntervalAsString:remainingTime];
}

#pragma mark - Controls

/* Prefer the toolbar for touches when in control view. */
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  if (self.fullscreen) {
    NSLog(@"TOUCH TEST");
    if (self.controlView.hidden) {
      [self didTouchControl:nil];
      return nil;
    } else if (point.y > self.frame.size.height - kToolbarHeight) {
      return [self.controlView hitTest:point withEvent:event];
    }
  }

  return [super hitTest:point withEvent:event];
}

/* Take the appropriate action when the play/pause button is clicked - depending
 * on the state this may start the movie, pause the movie, or start or pause
 * casting. */
- (IBAction)playButtonClicked:(id)sender {
  NSLog(@"playButtonClicked %d", _pendingPlay);

  id<LocalPlayerViewDelegate> delegate = self.delegate;
  if (self.playerState == LocalPlayerStateStopped && delegate &&
      [delegate respondsToSelector:@selector(continueAfterPlayButtonClicked)]) {
    if (!_delegate.continueAfterPlayButtonClicked) {
      return;
    }
  }
  self.recentInteraction = YES;

  if (self.playerState == LocalPlayerStateStopped) {
    [self loadMediaPlayer];
    self.slider.enabled = NO;
    [self.activityIndicator startAnimating];
    if (_mediaPlayer.currentItem &&
        !CMTIME_IS_INDEFINITE(_mediaPlayer.currentItem.duration)) {
      [self handleMediaPlayerReady];
    } else {
      self.playerState = LocalPlayerStateStarting;
    }
  } else if (self.playerState == LocalPlayerStatePlaying) {
    [_mediaPlayer pause];
    self.playerState = LocalPlayerStatePaused;
  } else if (self.playerState == LocalPlayerStatePaused) {
    [_mediaPlayer play];
    self.playerState = LocalPlayerStatePlaying;
  }

  [self configureControls];
}

/* If we touch the slider, stop the movie while we scrub. */
- (IBAction)onSliderTouchStarted:(id)sender {
  _mediaPlayer.rate = 0.f;
  self.recentInteraction = YES;
}

/* Once we let go of the slider, restart playback. */
- (IBAction)onSliderTouchEnded:(id)sender {
  _mediaPlayer.rate = 1.0f;
}

/* On slider value change the movie play time. */
- (IBAction)onSliderValueChanged:(id)sender {
  if (self.streamDuration) {
    CMTime newTime = CMTimeMakeWithSeconds(self.slider.value, 1);
    [self.activityIndicator startAnimating];
    [_mediaPlayer seekToTime:newTime];
  } else {
    self.slider.value = 0;
  }
}

/* Config the UIView controls container based on the state of the view. */
- (void)configureControls {
  NSLog(@"configureControls %ld", (long)self.playerState);
  if (self.playerState == LocalPlayerStateStopped) {
    [self.playButton setImage:self.playImage forState:UIControlStateNormal];
    self.splashPlayButton.hidden = NO;
    self.splashImage.layer.hidden = NO;
    _mediaPlayerLayer.hidden = YES;
    self.controlView.hidden = YES;

  } else if (self.playerState == LocalPlayerStatePlaying ||
             self.playerState == LocalPlayerStatePaused ||
             self.playerState == LocalPlayerStateStarting) {
    // Play or Pause button based on state.
    UIImage *image = self.playerState == LocalPlayerStatePaused
                         ? self.playImage
                         : self.pauseImage;
    [self.playButton setImage:image forState:UIControlStateNormal];
    self.playButton.hidden = NO;
    self.splashPlayButton.hidden = YES;

    _mediaPlayerLayer.hidden = NO;
    self.splashImage.layer.hidden = YES;
    self.controlView.hidden = NO;
  }
  [self didTouchControl:nil];
  [self setNeedsLayout];
}

- (void)showControls {
  self.toolbarView.hidden = NO;
}

- (void)hideControls {
  self.toolbarView.hidden = YES;
  if (self.fullscreen) {
    NSLog(@"hideNavigationBar: hide controls");
    [_delegate hideNavigationBar:YES];
  }
}

/* Initial setup of the controls in the toolbar. */
- (void)initialiseToolbarControls {
  CGRect frame = [self fullFrame];

  // Play/Pause images.
  self.playImage = [UIImage imageNamed:@"play"];
  self.pauseImage = [UIImage imageNamed:@"pause"];

  // Toolbar.
  self.toolbarView = [[UIView alloc] init];
  [self layoutToolbar:frame];

  // Background gradient
  CAGradientLayer *gradient = [CAGradientLayer layer];
  gradient.frame = self.toolbarView.bounds;
  gradient.colors = @[(id)[UIColor clearColor].CGColor,
                       (id)[UIColor colorWithRed:(50 / 255.0)
                                            green:(50 / 255.0)
                                             blue:(50 / 255.0)
                                            alpha:(200 / 255.0)].CGColor];
  gradient.startPoint = CGPointZero;
  gradient.endPoint = CGPointMake(0, 1);

  // Play/Pause button.
  self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
  (self.playButton).frame = CGRectMake(0, 0, 40, 40);
  [self.playButton setImage:self.playImage forState:UIControlStateNormal];
  [self.playButton addTarget:self
                      action:@selector(playButtonClicked:)
            forControlEvents:UIControlEventTouchUpInside];
  self.playButton.tintColor = [UIColor whiteColor];
  self.playButton.translatesAutoresizingMaskIntoConstraints = NO;

  // Total time.
  self.totalTime = [[UILabel alloc] init];
  self.totalTime.clearsContextBeforeDrawing = YES;
  self.totalTime.text = @"00:00";
  (self.totalTime).font = [UIFont fontWithName:@"Helvetica" size:14.0];
  (self.totalTime).textColor = [UIColor whiteColor];
  self.totalTime.tintColor = [UIColor whiteColor];
  self.totalTime.translatesAutoresizingMaskIntoConstraints = NO;

  // Slider.
  self.slider = [[UISlider alloc] init];
  UIImage *thumb = [UIImage imageNamed:@"thumb"];
  // TODO new image
  [self.slider setThumbImage:thumb forState:UIControlStateNormal];
  [self.slider setThumbImage:thumb forState:UIControlStateHighlighted];
  [self.slider addTarget:self
                  action:@selector(onSliderValueChanged:)
        forControlEvents:UIControlEventValueChanged];
  [self.slider addTarget:self
                  action:@selector(onSliderTouchStarted:)
        forControlEvents:UIControlEventTouchDown];
  [self.slider addTarget:self
                  action:@selector(onSliderTouchEnded:)
        forControlEvents:UIControlEventTouchUpInside];
  [self.slider addTarget:self
                  action:@selector(onSliderTouchEnded:)
        forControlEvents:UIControlEventTouchCancel];
  [self.slider addTarget:self
                  action:@selector(onSliderTouchEnded:)
        forControlEvents:UIControlEventTouchUpOutside];
  self.slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  self.slider.minimumValue = 0;
  self.slider.minimumTrackTintColor = [UIColor colorWithRed:15.0 / 255
                                                      green:153.0 / 255
                                                       blue:242.0 / 255
                                                      alpha:1.0];
  self.slider.translatesAutoresizingMaskIntoConstraints = NO;

  [self.toolbarView addSubview:self.playButton];
  [self.toolbarView addSubview:self.totalTime];
  [self.toolbarView addSubview:self.slider];
  [self.toolbarView.layer insertSublayer:gradient atIndex:0];
  [self.controlView insertSubview:self.toolbarView atIndex:0];

  self.activityIndicator = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
  self.activityIndicator.hidesWhenStopped = YES;
  [self.controlView insertSubview:self.activityIndicator
                     aboveSubview:self.toolbarView];

  // Layout.
  NSString *hlayout = @"|-[playButton(==40)]-5-[slider(>=120)]"
                      @"-[totalTime(>=40)]-|";
  NSString *vlayout = @"V:|[playButton(==40)]";
  self.viewsDictionary = @{
    @"slider" : self.slider,
    @"totalTime" : self.totalTime,
    @"playButton" : self.playButton
  };
  [self.toolbarView
      addConstraints:
          [NSLayoutConstraint
              constraintsWithVisualFormat:hlayout
                                  options:NSLayoutFormatAlignAllCenterY
                                  metrics:nil
                                    views:self.viewsDictionary]];
  [self.toolbarView
      addConstraints:[NSLayoutConstraint
                         constraintsWithVisualFormat:vlayout
                                             options:0
                                             metrics:nil
                                               views:self.viewsDictionary]];
}

/* Hide the tool bar, and the navigation controller if in the appropriate state.
 * If there has been a recent interaction, retry in kToolbarDelay seconds. */
- (void)hideToolBar {
  NSLog(@"hideToolBar %ld", (long)self.playerState);
  if (!(self.playerState == LocalPlayerStatePlaying ||
        self.playerState == LocalPlayerStateStarting)) {
    return;
  }
  if (self.recentInteraction) {
    self.recentInteraction = NO;
    [self performSelector:@selector(hideToolBar)
               withObject:self
               afterDelay:kToolbarDelay];
  } else {
    [UIView animateWithDuration:0.5
        animations:^{
          (self.toolbarView).alpha = 0;
        }
        completion:^(BOOL finished) {
          [self hideControls];
          (self.toolbarView).alpha = 1;
        }];
  }
}

/* Called when used touches the controlView. Display the controls, and if the
 * user is playing
 * set a timeout to hide them again. */
- (void)didTouchControl:(id)sender {
  NSLog(@"didTouchControl %ld", (long)self.playerState);
  [self showControls];
  NSLog(@"hideNavigationBar: did touch control");
  [_delegate hideNavigationBar:NO];
  self.recentInteraction = YES;
  if (self.playerState == LocalPlayerStatePlaying ||
      self.playerState == LocalPlayerStateStarting) {
    [self performSelector:@selector(hideToolBar)
               withObject:self
               afterDelay:kToolbarDelay];
  }
}

#pragma mark - KVO

// Register observers for the media time callbacks and for the end of playback
// notification.
- (void)addMediaPlayerObservers {
  NSLog(@"addMediaPlayerObservers");
  // We take a weak reference to self to avoid retain cycles in the block.
  __weak LocalPlayerView *weakSelf = self;
  _mediaTimeObserver = [_mediaPlayer
      addPeriodicTimeObserverForInterval:CMTimeMake(1, 1)
                                   queue:NULL
                              usingBlock:^(CMTime time) {
                                LocalPlayerView *strongSelf = weakSelf;
                                if (strongSelf) {
                                  [strongSelf notifyStreamPositionChanged:time];
                                }
                              }];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleMediaPlaybackEnded)
             name:AVPlayerItemDidPlayToEndTimeNotification
           object:_mediaPlayer.currentItem];

  [_mediaPlayer.currentItem addObserver:self
                             forKeyPath:@"playbackBufferEmpty"
                                options:NSKeyValueObservingOptionNew
                                context:nil];
  [_mediaPlayer.currentItem addObserver:self
                             forKeyPath:@"playbackLikelyToKeepUp"
                                options:NSKeyValueObservingOptionNew
                                context:nil];
  [_mediaPlayer.currentItem addObserver:self
                             forKeyPath:@"status"
                                options:NSKeyValueObservingOptionNew
                                context:nil];
  _observingMediaPlayer = YES;
}

- (void)removeMediaPlayerObservers {
  NSLog(@"removeMediaPlayerObservers");
  if (_observingMediaPlayer) {
    if (_mediaTimeObserver) {
      [_mediaPlayer removeTimeObserver:_mediaTimeObserver];
      _mediaTimeObserver = nil;
    }

    if (_mediaPlayer.currentItem) {
      [[NSNotificationCenter defaultCenter]
          removeObserver:self
                    name:AVPlayerItemDidPlayToEndTimeNotification
                  object:_mediaPlayer.currentItem];
    }

    [_mediaPlayer.currentItem removeObserver:self
                                  forKeyPath:@"playbackBufferEmpty"];
    [_mediaPlayer.currentItem removeObserver:self
                                  forKeyPath:@"playbackLikelyToKeepUp"];
    [_mediaPlayer.currentItem removeObserver:self forKeyPath:@"status"];
    _observingMediaPlayer = NO;
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  NSLog(@"observeValueForKeyPath %@", keyPath);
  if (!_mediaPlayer.currentItem || (object != _mediaPlayer.currentItem)) {
    return;
  }

  if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
    [_activityIndicator stopAnimating];
  } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
    [_activityIndicator startAnimating];
  } else if ([keyPath isEqualToString:@"status"]) {
    if (_mediaPlayer.status == AVPlayerStatusReadyToPlay) {
      [self handleMediaPlayerReady];
    }
  }
}

@end
