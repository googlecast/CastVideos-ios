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

import Foundation
import GoogleCast

/**
 * An object representing a media item (or a container group of media items).
 */
class MediaItem: NSObject {
  fileprivate(set) var title: String?
  fileprivate(set) var imageURL: URL?
  var children: [Any]!
  fileprivate(set) var mediaInfo: GCKMediaInformation?
  fileprivate(set) var parent: MediaItem?
  var isNowPlaying: Bool = false

  /** Initializer for constructing a group item.
   *
   * @param title The title of the item.
   * @param imageURL The URL of the image for this item.
   * @param parent The parent item of this item, if any.
   */
  init(title: String?, imageURL: URL?, parent: MediaItem?) {
    self.title = title
    children = [Any]()
    self.imageURL = imageURL
    self.parent = parent
  }

  /** Initializer for constructing a media item.
   *
   * @param mediaInfo The media information for this item.
   * @param parent The parent item of this item, if any.
   */
  convenience init(mediaInformation mediaInfo: GCKMediaInformation, parent: MediaItem) {
    let title = mediaInfo.metadata?.string(forKey: kGCKMetadataKeyTitle) ?? ""
    let imageURL = (mediaInfo.metadata?.images()[0] as? GCKImage)?.url
    self.init(title: title, imageURL: imageURL, parent: parent)
    self.mediaInfo = mediaInfo
  }

  /**
   * Factory method for constructing the special "now playing" item.
   *
   * @param parent The parent item of this item.
   */
  class func nowPlayingItem(withParent parent: MediaItem) -> MediaItem {
    let item = MediaItem(title: "Now Playing", imageURL: nil, parent: parent)
    item.isNowPlaying = true
    return item
  }
}
