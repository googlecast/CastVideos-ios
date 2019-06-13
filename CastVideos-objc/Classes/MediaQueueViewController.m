// Copyright 2019 Google LLC. All Rights Reserved.
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

#import "MediaQueueViewController.h"

#import <GoogleCast/GoogleCast.h>

#import "AppDelegate.h"
#import "MediaItem.h"

@interface MediaQueueViewController () <UITableViewDataSource,
                                        UITableViewDelegate,
                                        GCKSessionManagerListener,
                                        GCKRemoteMediaClientListener,
                                        GCKRequestDelegate> {
  NSTimer *_timer;

  // Queue
  IBOutlet UITableView *_tableView;

  // Queue/editing state.
  IBOutlet UIBarButtonItem *_editButton;
  BOOL _editing;

  GCKRemoteMediaClient *_mediaClient;
  GCKUIMediaController *_mediaController;
  GCKRequest *_queueRequest;
}

@end

@implementation MediaQueueViewController

- (void)viewDidLoad {
  NSLog(@"_tableView is %@", _tableView);
  _tableView.dataSource = self;
  _tableView.delegate = self;

  _editing = NO;

  GCKSessionManager *sessionManager = [GCKCastContext sharedInstance].sessionManager;
  [sessionManager addListener:self];
  if (sessionManager.hasConnectedCastSession) {
    [self attachToCastSession:sessionManager.currentCastSession];
  }

  UILongPressGestureRecognizer *recognizer =
      [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
  recognizer.minimumPressDuration = 2.0;  // 2 seconds
  [_tableView addGestureRecognizer:recognizer];
  _tableView.separatorColor = [UIColor clearColor];

  [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
  appDelegate.castControlBarsEnabled = NO;
  [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  _queueRequest = nil;
  _tableView.userInteractionEnabled = YES;

  if ([_mediaClient.mediaStatus queueItemCount] == 0) {
    [_editButton setEnabled:NO];
  } else {
    [_editButton setEnabled:YES];
  }

  [_tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
}

#pragma mark - UI Actions

- (IBAction)toggleEditing:(id)sender {
  if (_editing) {
    _editButton.title = @"Edit";
    [_tableView setEditing:NO animated:YES];
    _editing = NO;
    if ([_mediaClient.mediaStatus queueItemCount] == 0) {
      [_editButton setEnabled:NO];
    }
  } else {
    _editButton.title = @"Done";
    [_tableView setEditing:YES animated:YES];
    _editing = YES;
  }
}

- (void)showErrorMessage:(NSString *)message {
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil)
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                        otherButtonTitles:nil];
  [alert show];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
  CGPoint point = [gestureRecognizer locationInView:_tableView];
  NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:point];
  if (indexPath) {
    GCKMediaQueueItem *item = [_mediaClient.mediaStatus queueItemAtIndex:indexPath.row];
    if (item) {
      [self startRequest:[_mediaClient queueJumpToItemWithID:item.itemID]];
    }
  }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  if (!_mediaClient || !_mediaClient.mediaStatus) {
    return 0;
  }

  return _mediaClient.mediaStatus.queueItemCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MediaCell"];

  GCKMediaQueueItem *item = [_mediaClient.mediaStatus queueItemAtIndex:indexPath.row];

  NSString *title = [item.mediaInformation.metadata stringForKey:kGCKMetadataKeyTitle];
  NSString *artist = [item.mediaInformation.metadata stringForKey:kGCKMetadataKeyArtist];
  if (!artist) {
    NSString *value = [item.mediaInformation.metadata stringForKey:kGCKMetadataKeyStudio];
    artist = value ? value : @"";
  }

  NSString *duration = (item.mediaInformation.streamDuration == INFINITY) ? @"" : [GCKUIUtils timeIntervalAsString:item.mediaInformation.streamDuration];
  NSString *detail = [NSString
      stringWithFormat:@"(%@) %@",
                       duration,
                       artist];
  UILabel *mediaTitle = (UILabel *)[cell viewWithTag:1];
  mediaTitle.text = title;

  UILabel *mediaOwner = (UILabel *)[cell viewWithTag:2];
  mediaOwner.text = detail;

  if (_mediaClient.mediaStatus.currentItemID == item.itemID) {
    cell.backgroundColor = [UIColor colorWithRed:15.0 / 255
                                           green:153.0 / 255
                                            blue:242.0 / 255
                                           alpha:0.1];
  } else {
    cell.backgroundColor = nil;
  }

  UIImageView *imageView = (UIImageView *)[cell.contentView viewWithTag:3];

  NSArray *images = item.mediaInformation.metadata.images;
  if (images && images.count > 0) {
    GCKImage *image = images[0];

    [[GCKCastContext sharedInstance].imageCache fetchImageForURL:image.URL
                                                      completion:^(UIImage *image) {
                                                        imageView.image = image;
                                                        [cell setNeedsLayout];
                                                      }];
  }

  return cell;
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
  return YES;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
  if (sourceIndexPath.row == destinationIndexPath.row) {
    return;
  }
  GCKMediaQueueItem *sourceItem = [_mediaClient.mediaStatus queueItemAtIndex:sourceIndexPath.row];
  NSUInteger insertBeforeID = kGCKMediaQueueInvalidItemID;

  if (destinationIndexPath.row < (NSInteger)[_mediaClient.mediaStatus queueItemCount] - 1) {
    GCKMediaQueueItem *beforeItem =
        [_mediaClient.mediaStatus queueItemAtIndex:destinationIndexPath.row];
    insertBeforeID = beforeItem.itemID;
  }

  [self startRequest:[_mediaClient queueMoveItemWithID:sourceItem.itemID
                                      beforeItemWithID:insertBeforeID]];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
  return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
  if (editingStyle == UITableViewCellEditingStyleDelete) {
    // Delete row.
    GCKMediaQueueItem *item = [_mediaClient.mediaStatus queueItemAtIndex:indexPath.row];
    if (item) {
      [self startRequest:[_mediaClient queueRemoveItemWithID:item.itemID]];
    }
  }
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
  // No-op.
}

#pragma mark - Session handling

- (void)attachToCastSession:(GCKCastSession *)castSession {
  _mediaClient = castSession.remoteMediaClient;
  [_mediaClient addListener:self];
  [_tableView reloadData];
}

- (void)detachFromCastSession {
  [_mediaClient removeListener:self];
  _mediaClient = nil;
  [_tableView reloadData];
}

#pragma mark - GCKSessionManagerListener

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didStartCastSession:(GCKCastSession *)session {
  [self attachToCastSession:session];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didSuspendCastSession:(GCKCastSession *)session
               withReason:(GCKConnectionSuspendReason)reason {
  [self detachFromCastSession];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didResumeCastSession:(GCKCastSession *)session {
  [self attachToCastSession:session];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    willEndCastSession:(GCKCastSession *)session {
  [self detachFromCastSession];
}

#pragma mark - GCKRemoteMediaClientListener

- (void)remoteMediaClient:(GCKRemoteMediaClient *)client
     didUpdateMediaStatus:(GCKMediaStatus *)mediaStatus {
  [_tableView reloadData];
}

- (void)remoteMediaClientDidUpdateQueue:(GCKRemoteMediaClient *)client {
  [_tableView reloadData];
}

#pragma mark - Request scheduling

- (void)startRequest:(GCKRequest *)request {
  _queueRequest = request;
  _queueRequest.delegate = self;
  _tableView.userInteractionEnabled = NO;
}

#pragma mark - GCKRequestDelegate

- (void)requestDidComplete:(GCKRequest *)request {
  if (request == _queueRequest) {
    _queueRequest = nil;
    _tableView.userInteractionEnabled = YES;
  }
}

- (void)request:(GCKRequest *)request didFailWithError:(GCKError *)error {
  if (request == _queueRequest) {
    _queueRequest = nil;
    _tableView.userInteractionEnabled = YES;
    [self showErrorMessage:[NSString
                               stringWithFormat:@"Queue request failed:\n%@", error.description]];
  }
}

- (void)requestWasReplaced:(GCKRequest *)request {
  if (request == _queueRequest) {
    _queueRequest = nil;
    _tableView.userInteractionEnabled = YES;
  }
}

@end
