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

#import <Foundation/Foundation.h>

/** A key for the URL of the media item's poster (large image). */
extern NSString *const kMediaKeyPosterURL;
/** A key for the media item's extended description. */
extern NSString *const kMediaKeyDescription;

@class MediaInformation;
@class MediaItem;

@protocol MediaListModelDelegate;

/**
 * An object representing a hierarchy of media items.
 */
@interface MediaListModel : NSObject

/** A delegate for receiving notifications from the model. */
@property(nonatomic, weak) id<MediaListModelDelegate> delegate;

/** A flag indicating whether the model has been loaded. */
@property(nonatomic, assign, readonly) BOOL loaded;

/**
 * Begins loading the model from the given URL. The delegate will be messaged
 * when the load
 * completes or fails.
 *
 * @param url The URL of the JSON file describing the media hierarchy.
 */
- (void)loadFromURL:(NSURL *)url;

/** The title of the media list. */
@property(nonatomic, readonly) NSString *title;

/* The root item (top-level group). */
@property(nonatomic, readonly) MediaItem *rootItem;

@end

/**
 * The delegate protocol for receiving notifications from the model.
 */
@protocol MediaListModelDelegate<NSObject>

/**
 * Called when the media list has loaded.
 *
 * @param list The media list.
 */
- (void)mediaListModelDidLoad:(MediaListModel *)list;

/**
 * Called when the media list has failed to load.
 *
 * @param list The media list.
 * @param error The error.
 */
- (void)mediaListModel:(MediaListModel *)list
didFailToLoadWithError:(NSError *)error;

@end
