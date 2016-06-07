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

#import <UIKit/UIKit.h>

@class MediaListModel;

extern NSString *const kApplicationID;

extern NSString *const kPrefPreloadTime;

@interface AppDelegate : UIResponder<UIApplicationDelegate>

@property(nonatomic, strong, readwrite) UIWindow *window;
@property(nonatomic, strong, readwrite) MediaListModel *mediaList;
@property(nonatomic, assign, readwrite) BOOL castControlBarsEnabled;

@end

#define appDelegate ((AppDelegate *)[UIApplication sharedApplication].delegate)
