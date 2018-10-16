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

#import <objc/runtime.h>

@interface ActionSheetAction : NSObject

@property(nonatomic, copy, readonly) NSString *title;

- (instancetype)initWithTitle:(NSString *)title
                       target:(id)target
                     selector:(SEL)selector NS_DESIGNATED_INITIALIZER;

- (void)trigger;

@end

@implementation ActionSheetAction {
  __weak id _target;
  SEL _selector;
}

- (instancetype)initWithTitle:(NSString *)title
                       target:(id)target
                     selector:(SEL)selector {
  if (self = [super init]) {
    _title = title;
    _target = target;
    _selector = selector;
  }
  return self;
}

- (void)trigger {
  if (_target && _selector && [_target respondsToSelector:_selector]) {
    // See http://stackoverflow.com/questions/7017281
    IMP imp = [_target methodForSelector:_selector];
    void (*func)(id, SEL) = (void *)imp;
    func(_target, _selector);
  }
}

@end

@interface ActionSheet ()<UIAlertViewDelegate>

@end

@implementation ActionSheet {
  NSString *_title;
  NSString *_message;
  NSString *_cancelButtonText;
  NSMutableArray<ActionSheetAction *> *_actions;
  NSMutableDictionary<NSNumber *, ActionSheetAction *> *_indexedActions;
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
             cancelButtonText:(NSString *)cancelButtonText {
  if ((self = [super init])) {
    _title = title;
    _message = message;
    _cancelButtonText = cancelButtonText;
    _actions = [NSMutableArray array];
  }
  return self;
}

- (void)addActionWithTitle:(NSString *)title
                    target:(id)target
                  selector:(SEL)selector {
  ActionSheetAction *action =
      [[ActionSheetAction alloc] initWithTitle:title
                                        target:target
                                      selector:selector];
  [_actions addObject:action];
}

- (void)presentInController:(UIViewController *)parent
                 sourceView:(UIView *)sourceView {
  if ([UIAlertController class]) {
    // iOS 8+ approach.
    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:_title
                         message:_message
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (ActionSheetAction *action in _actions) {
      UIAlertAction *alertAction =
          [UIAlertAction actionWithTitle:action.title
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *unused) {
                                   [action trigger];
                                 }];
      [controller addAction:alertAction];
    }

    if (_cancelButtonText) {
      UIAlertAction *cancelAction = [UIAlertAction
          actionWithTitle:_cancelButtonText
                    style:UIAlertActionStyleCancel
                  handler:^(UIAlertAction *action) {
                    [controller dismissViewControllerAnimated:YES
                                                   completion:nil];
                  }];
      [controller addAction:cancelAction];
    }

    // Present the controller in the right location, on iPad. On iPhone, it
    // always displays at the
    // bottom of the screen.
    UIPopoverPresentationController *presentationController =
        controller.popoverPresentationController;
    presentationController.sourceView = sourceView;
    presentationController.sourceRect = sourceView.bounds;
    presentationController.permittedArrowDirections = 0;

    [parent presentViewController:controller animated:YES completion:nil];
  } else {
    // iOS 7 and below.
    UIAlertView *alertView =
        [[UIAlertView alloc] initWithTitle:_title
                                   message:_message
                                  delegate:self
                         cancelButtonTitle:_cancelButtonText
                         otherButtonTitles:nil];

    _indexedActions =
        [NSMutableDictionary dictionaryWithCapacity:_actions.count];
    for (ActionSheetAction *action in _actions) {
      NSInteger position = [alertView addButtonWithTitle:action.title];
      _indexedActions[@(position)] = action;
    }
    [alertView show];

    // Hold onto this ActionSheet until the UIAlertView is dismissed. This
    // ensures that the delegate
    // is not released (as UIAlertView usually only holds a weak reference to
    // us).
    static char kActionSheetKey;
    objc_setAssociatedObject(alertView, &kActionSheetKey, self,
                             OBJC_ASSOCIATION_RETAIN);
  }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView
    clickedButtonAtIndex:(NSInteger)buttonIndex {
  ActionSheetAction *action = _indexedActions[@(buttonIndex)];
  if (action) {
    [action trigger];
  }
}

- (void)alertViewCancel:(UIAlertView *)alertView {
  _indexedActions = nil;
}

@end
