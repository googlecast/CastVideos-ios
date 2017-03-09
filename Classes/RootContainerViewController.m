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
#import "RootContainerViewController.h"

#import <GoogleCast/GoogleCast.h>

#import <UIKit/UIKit.h>

static const NSTimeInterval kCastControlBarsAnimationDuration = 0.20;

@interface RootContainerViewController ()<
    GCKUIMiniMediaControlsViewControllerDelegate> {
  __weak IBOutlet UIView *miniMediaControlsContainerView;
  __weak IBOutlet NSLayoutConstraint *miniMediaControlsHeightConstraint;
  GCKUIMiniMediaControlsViewController *miniMediaControlsViewController;
}

@property(nonatomic, weak, readwrite)
    UINavigationController *navigationController;

@end

@implementation RootContainerViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  GCKCastContext *castContext = [GCKCastContext sharedInstance];
  miniMediaControlsViewController =
      [castContext createMiniMediaControlsViewController];
  miniMediaControlsViewController.delegate = self;

  [self updateControlBarsVisibility];
  [self installViewController:miniMediaControlsViewController
              inContainerView:miniMediaControlsContainerView];
}

- (void)setMiniMediaControlsViewEnabled:(BOOL)miniMediaControlsViewEnabled {
  _miniMediaControlsViewEnabled = miniMediaControlsViewEnabled;
  if (self.isViewLoaded) {
    [self updateControlBarsVisibility];
  }
}

#pragma mark - Internal methods

- (void)updateControlBarsVisibility {
  if (self.miniMediaControlsViewEnabled &&
      miniMediaControlsViewController.active) {
    miniMediaControlsHeightConstraint.constant =
        miniMediaControlsViewController.minHeight;
    [self.view bringSubviewToFront:miniMediaControlsContainerView];
  } else {
    miniMediaControlsHeightConstraint.constant = 0;
  }
  [UIView animateWithDuration:kCastControlBarsAnimationDuration
                   animations:^{
                     [self.view layoutIfNeeded];
                   }];
  [self.view setNeedsLayout];
}

- (void)installViewController:(UIViewController *)viewController
              inContainerView:(UIView *)containerView {
  if (viewController) {
    [self addChildViewController:viewController];
    viewController.view.frame = containerView.bounds;
    [containerView addSubview:viewController.view];
    [viewController didMoveToParentViewController:self];
  }
}

- (void)uninstallViewController:(UIViewController *)viewController {
  [viewController willMoveToParentViewController:nil];
  [viewController.view removeFromSuperview];
  [viewController removeFromParentViewController];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  if ([segue.identifier isEqualToString:@"NavigationVCEmbedSegue"]) {
    self.navigationController =
        (UINavigationController *)segue.destinationViewController;
  }
}

#pragma mark - GCKUIMiniMediaControlsViewControllerDelegate

- (void)miniMediaControlsViewController:(GCKUIMiniMediaControlsViewController *)
                                            miniMediaControlsViewController
                           shouldAppear:(BOOL)shouldAppear {
  [self updateControlBarsVisibility];
}

@end
