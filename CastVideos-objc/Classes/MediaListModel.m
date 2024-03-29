// Copyright 2022 Google LLC. All Rights Reserved.
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

#import "MediaListModel.h"

#import <GoogleCast/GoogleCast.h>

#import "MediaItem.h"

NSString *const kMediaKeyPosterURL = @"posterUrl";
NSString *const kMediaKeyDescription = @"description";

static NSString *const kKeyCategories = @"categories";
static NSString *const kKeyHlsBaseURL = @"hls";
static NSString *const kKeyImagesBaseURL = @"images";
static NSString *const kKeyTracksBaseURL = @"tracks";
static NSString *const kKeySources = @"sources";
static NSString *const kKeyVideos = @"videos";
static NSString *const kKeyArtist = @"artist";
static NSString *const kKeyBaseURL = @"baseUrl";
static NSString *const kKeyContentID = @"contentId";
static NSString *const kKeyDescription = @"description";
static NSString *const kKeyID = @"id";
static NSString *const kKeyImageURL = @"image-480x270";
static NSString *const kKeyItems = @"items";
static NSString *const kKeyLanguage = @"language";
static NSString *const kKeyMimeType = @"mime";
static NSString *const kKeyName = @"name";
static NSString *const kKeyPosterURL = @"image-780x1200";
static NSString *const kKeyStreamType = @"streamType";
static NSString *const kKeyStudio = @"studio";
static NSString *const kKeySubtitle = @"subtitle";
static NSString *const kKeySubtype = @"subtype";
static NSString *const kKeyTitle = @"title";
static NSString *const kKeyTracks = @"tracks";
static NSString *const kKeyType = @"type";
static NSString *const kKeyURL = @"url";
static NSString *const kKeyDuration = @"duration";

static NSString *const kDefaultVideoMimeType = @"application/x-mpegurl";
static NSString *const kDefaultTrackMimeType = @"text/vtt";

static NSString *const kTypeAudio = @"audio";
static NSString *const kTypePhoto = @"photos";
static NSString *const kTypeVideo = @"videos";

static NSString *const kTypeLive = @"live";

static const NSInteger kThumbnailWidth = 480;
static const NSInteger kThumbnailHeight = 720;

static const NSInteger kPosterWidth = 780;
static const NSInteger kPosterHeight = 1200;

@interface MediaListModel () {
  NSURLSession *_session;
  NSURLSessionDataTask *_dataTask;
  GCKMediaTextTrackStyle *_trackStyle;
  MediaItem *_rootItem;
}

@property(nonatomic, readwrite) NSString *title;
@property(nonatomic, assign, readwrite) BOOL loaded;

@end

@implementation MediaListModel {
  /** Storage for the list of Media objects. */
  NSArray *_medias;
}

- (instancetype)init {
  if (self = [super init]) {
    _trackStyle = [GCKMediaTextTrackStyle createDefault];
    _session = [NSURLSession sessionWithConfiguration: [NSURLSessionConfiguration defaultSessionConfiguration]];

  }
  return self;
}

- (void)loadFromURL:(NSURL *)url {
  _rootItem = nil;

  GCKLog(@"loading media list from URL %@", url);

  if (_dataTask != nil) {
    [_dataTask cancel];
  }

  __weak MediaListModel *weakSelf = self;
  _dataTask = [_session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    if (error != nil) {
      GCKLog(@"httpRequest failed with %@", error);
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate mediaListModel:weakSelf didFailToLoadWithError:error];
      });
      return;
    }

    long responseStatus = ((NSHTTPURLResponse *)response).statusCode;

    GCKLog(@"httpRequest completed with %ld", responseStatus);
    if (responseStatus == 200) {
      NSError *error;
      NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                               options:kNilOptions
                                                                 error:&error];
      self->_rootItem = [weakSelf decodeMediaTreeFromJSON:jsonData];
      weakSelf.loaded = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate mediaListModelDidLoad:weakSelf];
      });
    } else {
      NSError *error = [[NSError alloc] initWithDomain:@"HTTP" code:responseStatus userInfo:nil];
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate mediaListModel:weakSelf didFailToLoadWithError:error];
      });
    }
  }];

  if (_dataTask != nil) {
    [_dataTask resume];
  }
}

- (MediaItem *)rootItem {
  return _rootItem;
}

#pragma mark - JSON decoding

- (MediaItem *)decodeMediaTreeFromJSON:(NSDictionary *)json {
  MediaItem *rootItem = [[MediaItem alloc] initWithTitle:nil imageURL:nil parent:nil];

  NSArray *categories = [json gck_arrayForKey:kKeyCategories];
  for (NSDictionary *categoryElement in categories) {
    if (![categoryElement isKindOfClass:[NSDictionary class]]) continue;

    NSDictionary *category = (NSDictionary *)categoryElement;

    NSArray *mediaList = [category gck_arrayForKey:kKeyVideos];
    if (mediaList && [mediaList isKindOfClass:[NSArray class]]) {
      self.title = [category gck_stringForKey:kKeyName];
      // Pick the MP4 files only
      NSString *videosBaseURLString = [category gck_stringForKey:kKeyHlsBaseURL];
      NSURL *videosBaseURL = [NSURL URLWithString:videosBaseURLString];
      NSString *imagesBaseURLString = [category gck_stringForKey:kKeyImagesBaseURL];
      NSURL *imagesBaseURL = [NSURL URLWithString:imagesBaseURLString];
      NSString *tracksBaseURLString = [category gck_stringForKey:kKeyTracksBaseURL];
      NSURL *tracksBaseURL = [NSURL URLWithString:tracksBaseURLString];
      [self decodeItemListFromArray:mediaList
                           intoItem:rootItem
                        videoFormat:kKeyHlsBaseURL
                      videosBaseURL:videosBaseURL
                      imagesBaseURL:imagesBaseURL
                      tracksBaseURL:tracksBaseURL];
      break;
    }
  }

  return rootItem;
}

- (NSURL *)buildURLWithString:(NSString *)string baseURL:(NSURL *)baseURL {
  if (!string) return nil;

  if ([string hasPrefix:@"http://"] || [string hasPrefix:@"https://"]) {
    return [NSURL URLWithString:string];
  } else {
    return [NSURL URLWithString:string relativeToURL:baseURL];
  }
}

- (void)decodeItemListFromArray:(NSArray *)array
                       intoItem:(MediaItem *)item
                    videoFormat:(NSString *)videoFormat
                  videosBaseURL:(NSURL *)videosBaseURL
                  imagesBaseURL:(NSURL *)imagesBaseURL
                  tracksBaseURL:(NSURL *)tracksBaseURL {
  for (NSDictionary *element in array) {
    if (![element isKindOfClass:[NSDictionary class]]) continue;

    NSDictionary *dict = (NSDictionary *)element;

    NSString *title = [dict gck_stringForKey:kKeyTitle];

    GCKMediaMetadata *metadata =
        [[GCKMediaMetadata alloc] initWithMetadataType:GCKMediaMetadataTypeMovie];
    [metadata setString:title forKey:kGCKMetadataKeyTitle];

    NSString *mimeType = nil;
    NSURL *url = nil;
    NSArray *sources = [dict gck_arrayForKey:kKeySources];
    for (id sourceElement in sources) {
      if (![sourceElement isKindOfClass:[NSDictionary class]]) continue;

      NSDictionary *sourceDict = (NSDictionary *)sourceElement;

      NSString *type = [sourceDict gck_stringForKey:kKeyType];
      if ([type isEqualToString:videoFormat]) {
        mimeType = [sourceDict gck_stringForKey:kKeyMimeType];
        NSString *urlText = [sourceDict gck_stringForKey:kKeyURL];
        url = [self buildURLWithString:urlText baseURL:videosBaseURL];
        break;
      }
    }

    NSString *imageURLString = [dict gck_stringForKey:kKeyImageURL];
    NSURL *imageURL = [self buildURLWithString:imageURLString baseURL:imagesBaseURL];
    if (imageURL) {
      [metadata addImage:[[GCKImage alloc] initWithURL:imageURL
                                                 width:kThumbnailWidth
                                                height:kThumbnailHeight]];
    }

    NSString *posterURLText = [dict gck_stringForKey:kKeyPosterURL];
    NSURL *posterURL = [self buildURLWithString:posterURLText baseURL:imagesBaseURL];
    if (posterURL) {
      [metadata setString:posterURL.absoluteString forKey:kMediaKeyPosterURL];
      [metadata addImage:[[GCKImage alloc] initWithURL:posterURL
                                                 width:kPosterWidth
                                                height:kPosterHeight]];
    }

    NSString *description = [dict gck_stringForKey:kKeySubtitle];
    if (description) {
      [metadata setString:description forKey:kMediaKeyDescription];
    }

    NSMutableArray *mediaTracks = nil;

    NSString *studio = [dict gck_stringForKey:kKeyStudio];
    [metadata setString:studio forKey:kGCKMetadataKeyStudio];

    NSInteger duration = [dict gck_integerForKey:kKeyDuration];

    mediaTracks = [[NSMutableArray alloc] init];

    NSArray *tracks = [dict gck_arrayForKey:kKeyTracks];
    for (id trackElement in tracks) {
      if (![trackElement isKindOfClass:[NSDictionary class]]) continue;

      NSDictionary *trackDict = (NSDictionary *)trackElement;

      NSInteger identifier = [trackDict gck_integerForKey:kKeyID];
      NSString *name = [trackDict gck_stringForKey:kKeyName];
      NSString *typeString = [trackDict gck_stringForKey:kKeyType];
      NSString *subtypeString = [trackDict gck_stringForKey:kKeySubtype];
      NSString *contentID = [trackDict gck_stringForKey:kKeyContentID];
      NSString *language = [trackDict gck_stringForKey:kKeyLanguage];

      NSURL *url = [self buildURLWithString:contentID baseURL:tracksBaseURL];

      GCKMediaTrack *mediaTrack =
          [[GCKMediaTrack alloc] initWithIdentifier:identifier
                                  contentIdentifier:url.absoluteString
                                        contentType:kDefaultTrackMimeType
                                               type:[self trackTypeFrom:typeString]
                                        textSubtype:[self textTrackSubtypeFrom:subtypeString]
                                               name:name
                                       languageCode:language
                                         customData:nil];
      [mediaTracks addObject:mediaTrack];
    }
    if (mediaTracks.count == 0) {
      mediaTracks = nil;
    }

    // Define information about the media item.
    GCKMediaInformationBuilder *mediaInfoBuilder =
        [[GCKMediaInformationBuilder alloc] initWithContentURL:url];
    mediaInfoBuilder.streamDuration = duration;
    mediaInfoBuilder.streamType = GCKMediaStreamTypeBuffered;
    mediaInfoBuilder.contentType = mimeType;
    mediaInfoBuilder.metadata = metadata;
    mediaInfoBuilder.mediaTracks = mediaTracks;
    mediaInfoBuilder.textTrackStyle = _trackStyle;
    GCKMediaInformation *mediaInfo = [mediaInfoBuilder build];

    MediaItem *childItem = [[MediaItem alloc] initWithMediaInformation:mediaInfo parent:item];
    [item.children addObject:childItem];
  }
}

- (GCKMediaTrackType)trackTypeFrom:(NSString *)string {
  if ([string isEqualToString:@"audio"]) {
    return GCKMediaTrackTypeAudio;
  }
  if ([string isEqualToString:@"text"]) {
    return GCKMediaTrackTypeText;
  }
  if ([string isEqualToString:@"video"]) {
    return GCKMediaTrackTypeVideo;
  }
  return GCKMediaTrackTypeUnknown;
}

- (GCKMediaTextTrackSubtype)textTrackSubtypeFrom:(NSString *)string {
  if ([string isEqualToString:@"captions"]) {
    return GCKMediaTextTrackSubtypeCaptions;
  }
  if ([string isEqualToString:@"chapters"]) {
    return GCKMediaTextTrackSubtypeChapters;
  }
  if ([string isEqualToString:@"descriptions"]) {
    return GCKMediaTextTrackSubtypeDescriptions;
  }
  if ([string isEqualToString:@"metadata"]) {
    return GCKMediaTextTrackSubtypeMetadata;
  }
  if ([string isEqualToString:@"subtitles"]) {
    return GCKMediaTextTrackSubtypeSubtitles;
  }

  return GCKMediaTextTrackSubtypeUnknown;
}

@end
