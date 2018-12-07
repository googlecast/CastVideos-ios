// Copyright 2018 Google LLC. All Rights Reserved.
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

#import <UIKit/UIKit.h>

@class GCKMediaInformation;

/* Navigation Bar styles/ */
typedef NS_ENUM(NSUInteger, LPVNavBarStyle) { LPVNavBarTransparent, LPVNavBarDefault };

@protocol LocalPlayerViewDelegate;

/* The player state. */
typedef NS_ENUM(NSInteger, LocalPlayerState) {
  LocalPlayerStateStopped,
  LocalPlayerStateStarting,
  LocalPlayerStatePlaying,
  LocalPlayerStatePaused
};

/* UIView for displaying a local player or splash screen. */
@interface LocalPlayerView : UIView

/* Delegate to use for callbacks for play/pause presses while in Cast mode. */
@property(nonatomic, weak, readwrite) id<LocalPlayerViewDelegate> delegate;
/* Local player elapsed time. */
@property(nonatomic, assign, readonly) NSTimeInterval streamPosition;
/* Local player media duration. */
@property(nonatomic, assign, readonly) NSTimeInterval streamDuration;
/* YES if the video is playing or paused in the local player. */
@property(nonatomic, readonly) BOOL playingLocally;
/* YES if the video is fullscreen. */
@property(nonatomic, assign, readonly) BOOL fullscreen;
/* The media we are playing. */
@property(nonatomic, strong, readonly) GCKMediaInformation *media;
/* The current player state. */
@property(nonatomic, assign, readonly) LocalPlayerState playerState;

/* Signal an orientation change has occurred. */
- (void)orientationChanged;
- (void)loadMedia:(GCKMediaInformation *)media
         autoPlay:(BOOL)autoPlay
     playPosition:(NSTimeInterval)playPosition;
- (void)pause;
- (void)play;
- (void)stop;
- (void)togglePause;
- (void)seekToTime:(NSTimeInterval)time;

/* Reset the state of the player to show the splash screen. */
- (void)showSplashScreen;

@end

/* Protocol for callbacks from the LocalPlayerView. */
@protocol LocalPlayerViewDelegate <NSObject>

/* Signal the requested style for the view. */
- (void)setNavigationBarStyle:(LPVNavBarStyle)style;
/* Request the navigation bar to be hidden or shown. */
- (void)hideNavigationBar:(BOOL)hide;

@optional

/* Play has beeen pressed in the LocalPlayerView.
 * Return NO to halt default actions, YES to continue as normal.
 */
@property(NS_NONATOMIC_IOSONLY, readonly) BOOL continueAfterPlayButtonClicked;

@end
