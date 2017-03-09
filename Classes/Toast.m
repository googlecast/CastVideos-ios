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

#import "Toast.h"

// Coordinate to ensure two toasts are never active at once.
static BOOL isToastActive;
static Toast *activeToast;

@interface Toast ()

@property(nonatomic, strong, readwrite) UILabel *messageLabel;

@end

@implementation Toast

- (instancetype)initWithFrame:(CGRect)frame {
  return [super initWithFrame:frame];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self removeFromSuperview];
  isToastActive = false;
}

+ (void)displayToastMessage:(NSString *)message
            forTimeInterval:(NSTimeInterval)timeInterval
                     inView:(UIView *)view {
  if (!isToastActive) {
    isToastActive = YES;

    // Compute toast frame dimensions.
    CGFloat hostHeight = view.frame.size.height;
    CGFloat hostWidth = view.frame.size.width;
    CGFloat horizontalOffset = 0;
    CGFloat toastHeight = 48;
    CGFloat toastWidth = hostWidth;
    CGFloat verticalOffset = hostHeight - toastHeight;
    CGRect toastRect =
        CGRectMake(horizontalOffset, verticalOffset, toastWidth, toastHeight);

    // Init and stylize the toast and message.
    Toast *toast = [[Toast alloc] initWithFrame:toastRect];
    toast.backgroundColor = [UIColor colorWithRed:(50 / 255.0)
                                            green:(50 / 255.0)
                                             blue:(50 / 255.0)
                                            alpha:1];
    toast.messageLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(0, 0, toastWidth, toastHeight)];
    toast.messageLabel.text = message;
    toast.messageLabel.textColor = [UIColor whiteColor];
    toast.messageLabel.textAlignment = NSTextAlignmentCenter;
    toast.messageLabel.font = [UIFont systemFontOfSize:18];
    toast.messageLabel.adjustsFontSizeToFitWidth = YES;

    // Put the toast on top of the host view.
    [toast addSubview:toast.messageLabel];
    [view insertSubview:toast aboveSubview:(view.subviews).lastObject];
    activeToast = toast;

    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(orientationChanged:)
               name:UIDeviceOrientationDidChangeNotification
             object:nil];

    // Set the toast's timeout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     [toast removeFromSuperview];
                     [[NSNotificationCenter defaultCenter] removeObserver:self];
                     isToastActive = NO;
                     activeToast = nil;
                   });
  }
}

+ (void)orientationChanged:(NSNotification *)notification {
  if (isToastActive) {
    [activeToast removeFromSuperview];
    isToastActive = NO;
  }
}

@end
