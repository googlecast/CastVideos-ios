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

#import "MediaItem.h"

#import <GoogleCast/GoogleCast.h>

@interface MediaItem ()

@property(nonatomic, strong, readwrite) NSString *title;
@property(nonatomic, strong, readwrite) NSURL *imageURL;
@property(nonatomic, strong, readwrite) NSMutableArray *children;
@property(nonatomic, strong, readwrite) GCKMediaInformation *mediaInfo;
@property(nonatomic, strong, readwrite) MediaItem *parent;
@property(nonatomic, assign, readwrite) BOOL nowPlaying;

@end

@implementation MediaItem

- (instancetype)initWithTitle:(NSString *)title
                     imageURL:(NSURL *)imageURL
                       parent:(MediaItem *)parent {
  if (self = [super init]) {
    _title = title;
    _children = [[NSMutableArray alloc] init];
    _imageURL = imageURL;
    _parent = parent;
  }
  return self;
}

- (instancetype)initWithMediaInformation:(GCKMediaInformation *)mediaInfo
                                  parent:(MediaItem *)parent {
  if (self = [super init]) {
    _mediaInfo = mediaInfo;
    _title = [mediaInfo.metadata stringForKey:kGCKMetadataKeyTitle];
    NSArray *images = mediaInfo.metadata.images;
    if (images && (images.count > 0)) {
      _imageURL = ((GCKImage *)images[0]).URL;
    }
    _parent = parent;
  }
  return self;
}

+ (instancetype)nowPlayingItemWithParent:(MediaItem *)parent {
  MediaItem *item = [[MediaItem alloc] initWithTitle:@"Now Playing"
                                            imageURL:nil
                                              parent:parent];
  item.nowPlaying = YES;
  return item;
}

@end
