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

#import <GoogleCast/GoogleCast.h>

#import "AppDelegate.h"
#import "MediaItem.h"
#import "MediaListModel.h"
#import "MediaTableViewController.h"
#import "MediaViewController.h"
#import "Toast.h"

static NSString *const kPrefMediaListURL = @"media_list_url";

@interface MediaTableViewController ()<
    GCKSessionManagerListener, MediaListModelDelegate, GCKRequestDelegate> {
  GCKSessionManager *_sessionManager;
  GCKCastSession *_castSession;
  UIImageView *_rootTitleView;
  UIView *_titleView;
  NSURL *_mediaListURL;
  UIBarButtonItem *_queueButton;
  ActionSheet *_actionSheet;
  MediaItem *selectedItem;
  BOOL _queueAdded;
  GCKUICastButton *_castButton;
}

/** The media to be displayed. */
@property(nonatomic) MediaListModel *mediaList;

@end

@implementation MediaTableViewController

- (void)setRootItem:(MediaItem *)rootItem {
  _rootItem = rootItem;
  self.title = rootItem.title;
  [self.tableView reloadData];
}

- (void)viewDidLoad {
  NSLog(@"MediaTableViewController - viewDidLoad");
  [super viewDidLoad];

  _sessionManager = [GCKCastContext sharedInstance].sessionManager;
  [_sessionManager addListener:self];

  _titleView = self.navigationItem.titleView;
  _rootTitleView = [[UIImageView alloc]
      initWithImage:[UIImage imageNamed:@"logo_castvideos.png"]];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(loadMediaList)
             name:NSUserDefaultsDidChangeNotification
           object:nil];
  if (!self.rootItem) {
    [self loadMediaList];
  }

  _castButton =
      [[GCKUICastButton alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
  _castButton.tintColor = [UIColor whiteColor];
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithCustomView:_castButton];

  _queueButton = [[UIBarButtonItem alloc]
      initWithImage:[UIImage imageNamed:@"playlist_white.png"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(didTapQueueButton:)];

  self.tableView.separatorColor = [UIColor clearColor];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(deviceOrientationDidChange:)
             name:UIDeviceOrientationDidChangeNotification
           object:nil];
  [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
        selector:@selector(castDeviceDidChange:)
            name:kGCKCastStateDidChangeNotification
          object:[GCKCastContext sharedInstance]];
}

- (void)castDeviceDidChange:(NSNotification *)notification {
  if ([GCKCastContext sharedInstance].castState != GCKCastStateNoDevicesAvailable) {
    // You can present the instructions on how to use Google Cast on
    // the first time the user uses you app
    [[GCKCastContext sharedInstance] presentCastInstructionsViewControllerOnceWithCastButton:_castButton];
  }
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
  [self.tableView reloadData];
}

- (void)setQueueButtonVisible:(BOOL)visible {
  if (visible && !_queueAdded) {
    NSMutableArray *barItems = [[NSMutableArray alloc]
        initWithArray:self.navigationItem.rightBarButtonItems];
    [barItems addObject:_queueButton];
    self.navigationItem.rightBarButtonItems = barItems;
    _queueAdded = YES;
  } else if (!visible && _queueAdded) {
    NSMutableArray *barItems = [[NSMutableArray alloc]
        initWithArray:self.navigationItem.rightBarButtonItems];
    [barItems removeObject:_queueButton];
    self.navigationItem.rightBarButtonItems = barItems;
    _queueAdded = NO;
  }
}

- (void)didTapQueueButton:(id)sender {
  [self performSegueWithIdentifier:@"MediaQueueSegue" sender:self];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  NSLog(@"viewWillAppear - Table view");

  [self.navigationController.navigationBar setTranslucent:NO];
  [self.navigationController.navigationBar
      setBackgroundImage:nil
           forBarMetrics:UIBarMetricsDefault];
  self.navigationController.navigationBar.shadowImage = nil;
  [[UIApplication sharedApplication]
      setStatusBarHidden:NO
           withAnimation:UIStatusBarAnimationFade];
  self.navigationController.interactivePopGestureRecognizer.enabled = YES;

  if (!self.rootItem.parent) {
    // If this is the root group, show stylized application title in the title
    // view.
    self.navigationItem.titleView = _rootTitleView;
  } else {
    // Otherwise show the title of the group in the title view.
    self.navigationItem.titleView = _titleView;
    self.title = self.rootItem.title;
  }
  appDelegate.castControlBarsEnabled = YES;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
  return (self.rootItem.children).count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell =
      [tableView dequeueReusableCellWithIdentifier:@"MediaCell"];

  MediaItem *item =
      (MediaItem *)(self.rootItem.children)[indexPath.row];

  NSString *detail = nil;
  GCKMediaInformation *mediaInfo = item.mediaInfo;
  if (mediaInfo) {
    detail = [mediaInfo.metadata stringForKey:kGCKMetadataKeyStudio];
    if (!detail) {
      detail = [mediaInfo.metadata stringForKey:kGCKMetadataKeyArtist];
    }
  }

  UILabel *mediaTitle = (UILabel *)[cell viewWithTag:1];
  UILabel *mediaOwner = (UILabel *)[cell viewWithTag:2];

  if ([mediaTitle respondsToSelector:@selector(setAttributedText:)]) {
    NSString *titleText = item.title;
    NSString *ownerText = detail;

    NSString *text =
        [NSString stringWithFormat:@"%@\n%@", titleText, ownerText];

    NSDictionary *attribs = @{
      NSForegroundColorAttributeName : mediaTitle.textColor,
      NSFontAttributeName : mediaTitle.font
    };
    NSMutableAttributedString *attributedText =
        [[NSMutableAttributedString alloc] initWithString:text
                                               attributes:attribs];

    UIColor *blackColor = [UIColor blackColor];
    NSRange titleTextRange = NSMakeRange(0, titleText.length);
    [attributedText setAttributes:@{
      NSForegroundColorAttributeName : blackColor
    }
                            range:titleTextRange];

    UIColor *lightGrayColor = [UIColor lightGrayColor];
    NSRange ownerTextRange =
        NSMakeRange(titleText.length + 1, ownerText.length);
    [attributedText setAttributes:@{
      NSForegroundColorAttributeName : lightGrayColor,
      NSFontAttributeName : [UIFont systemFontOfSize:12]
    }
                            range:ownerTextRange];

    mediaTitle.attributedText = attributedText;
    [mediaOwner setHidden:YES];
  } else {
    mediaTitle.text = item.title;
    mediaOwner.text = detail;
  }

  if (item.mediaInfo) {
    cell.accessoryType = UITableViewCellAccessoryNone;
  } else {
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }

  UIImageView *imageView = (UIImageView *)[cell.contentView viewWithTag:3];
  [[GCKCastContext sharedInstance]
          .imageCache fetchImageForURL:item.imageURL
                            completion:^(UIImage *image) {
                              imageView.image = image;
                              [cell setNeedsLayout];
                            }];

  UIButton *addButton = (UIButton *)[cell viewWithTag:4];
  BOOL hasConnectedCastSession =
      [GCKCastContext sharedInstance].sessionManager.hasConnectedCastSession;
  if (hasConnectedCastSession) {
    [addButton setHidden:NO];
    [addButton addTarget:self
                  action:@selector(playButtonClicked:)
        forControlEvents:UIControlEventTouchDown];
  } else {
    [addButton setHidden:YES];
  }

  return cell;
}

- (IBAction)playButtonClicked:(id)sender {
  UITableViewCell *tableViewCell =
      (UITableViewCell *)[sender superview].superview;
  NSIndexPath *indexPathForCell =
      [self.tableView indexPathForCell:tableViewCell];
  selectedItem =
      (MediaItem *)(self.rootItem.children)[indexPathForCell.row];
  BOOL hasConnectedCastSession =
      [GCKCastContext sharedInstance].sessionManager.hasConnectedCastSession;
  if (selectedItem.mediaInfo && hasConnectedCastSession) {
    // Display an popover to allow the user to add to queue or play
    // immediately.
    if (!_actionSheet) {
      _actionSheet = [[ActionSheet alloc] initWithTitle:@"Play Item"
                                                message:@"Select an action"
                                       cancelButtonText:@"Cancel"];
      [_actionSheet addActionWithTitle:@"Play Now"
                                target:self
                              selector:@selector(playSelectedItemRemotely)];
      [_actionSheet addActionWithTitle:@"Add to Queue"
                                target:self
                              selector:@selector(enqueueSelectedItemRemotely)];
    }
    [_actionSheet presentInController:self sourceView:tableViewCell];
  }
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  MediaItem *item = (self.rootItem.children)[indexPath.row];

  if (item.mediaInfo) {
    [self performSegueWithIdentifier:@"mediaDetails" sender:self];
  }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  NSLog(@"prepareForSegue");
  if ([segue.identifier isEqualToString:@"mediaDetails"]) {
    MediaViewController *viewController =
        (MediaViewController *)segue.destinationViewController;
    GCKMediaInformation *mediaInfo = [self getSelectedItem].mediaInfo;
    if (mediaInfo) {
      viewController.mediaInfo = mediaInfo;
    }
  }
}

- (void)playSelectedItemRemotely {
  [self loadSelectedItemByAppending:NO];
  [[GCKCastContext sharedInstance] presentDefaultExpandedMediaControls];
}

- (void)enqueueSelectedItemRemotely {
  [self loadSelectedItemByAppending:YES];
  // selectedItem = [self getSelectedItem];
  NSString *message =
      [NSString stringWithFormat:@"Added \"%@\" to queue.",
                                 [selectedItem.mediaInfo.metadata
                                     stringForKey:kGCKMetadataKeyTitle]];
  [Toast displayToastMessage:message
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:YES];
}

/**
 * Loads the currently selected item in the current cast media session.
 * @param appending If YES, the item is appended to the current queue if there
 * is one. If NO, or if
 * there is no queue, a new queue containing only the selected item is created.
 */
- (void)loadSelectedItemByAppending:(BOOL)appending {
  NSLog(@"enqueue item %@", selectedItem.mediaInfo);

  GCKSession *session =
      [GCKCastContext sharedInstance].sessionManager.currentSession;
  if ([session isKindOfClass:[GCKCastSession class]]) {
    GCKCastSession *castSession = (GCKCastSession *)session;
    if (castSession.remoteMediaClient) {
      GCKMediaQueueItemBuilder *builder =
          [[GCKMediaQueueItemBuilder alloc] init];
      builder.mediaInformation = selectedItem.mediaInfo;
      builder.autoplay = YES;
      builder.preloadTime = [[NSUserDefaults standardUserDefaults]
          integerForKey:kPrefPreloadTime];
      GCKMediaQueueItem *item = [builder build];
      if (castSession.remoteMediaClient.mediaStatus && appending) {
        GCKRequest *request = [castSession.remoteMediaClient
             queueInsertItem:item
            beforeItemWithID:kGCKMediaQueueInvalidItemID];
        request.delegate = self;
      } else {
        GCKMediaRepeatMode repeatMode =
            castSession.remoteMediaClient.mediaStatus
                ? castSession.remoteMediaClient.mediaStatus.queueRepeatMode
                : GCKMediaRepeatModeOff;

        GCKRequest *request =
            [castSession.remoteMediaClient queueLoadItems:@[ item ]
                                               startIndex:0
                                             playPosition:0
                                               repeatMode:repeatMode
                                               customData:nil];
        request.delegate = self;
      }
    }
  }
}

- (MediaItem *)getSelectedItem {
  MediaItem *item = nil;
  NSIndexPath *indexPath = (self.tableView).indexPathForSelectedRow;
  if (indexPath) {
    NSLog(@"selected row is %@", indexPath);
    item = (MediaItem *)(self.rootItem.children)[indexPath.row];
  }
  return item;
}

#pragma mark - MediaListModelDelegate

- (void)mediaListModelDidLoad:(MediaListModel *)list {
  self.rootItem = self.mediaList.rootItem;
  self.title = self.mediaList.title;

  [self.tableView reloadData];
}

- (void)mediaListModel:(MediaListModel *)list
didFailToLoadWithError:(NSError *)error {
  NSString *errorMessage =
      [NSString stringWithFormat:@"Unable to load the media list from\n%@.",
                                 _mediaListURL.absoluteString];
  UIAlertView *alert =
      [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cast Error", nil)
                                 message:NSLocalizedString(errorMessage, nil)
                                delegate:nil
                       cancelButtonTitle:NSLocalizedString(@"OK", nil)
                       otherButtonTitles:nil];
  [alert show];
}

- (void)loadMediaList {
  // Look up the media list URL.
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  NSString *urlKey = [userDefaults stringForKey:kPrefMediaListURL];
  NSString *urlText = [userDefaults stringForKey:urlKey];

  NSURL *mediaListURL = [NSURL URLWithString:urlText];

  if (_mediaListURL && [mediaListURL isEqual:_mediaListURL]) {
    // The URL hasn't changed; do nothing.
    return;
  }

  _mediaListURL = mediaListURL;

  // Asynchronously load the media json.
  AppDelegate *delegate =
      (AppDelegate *)[UIApplication sharedApplication].delegate;
  delegate.mediaList = [[MediaListModel alloc] init];
  self.mediaList = delegate.mediaList;
  self.mediaList.delegate = self;
  [self.mediaList loadFromURL:_mediaListURL];
}

#pragma mark - GCKSessionManagerListener

- (void)sessionManager:(GCKSessionManager *)sessionManager
       didStartSession:(GCKSession *)session {
  NSLog(@"MediaViewController: sessionManager didStartSession %@", session);
  [self setQueueButtonVisible:YES];
  [self.tableView reloadData];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
      didResumeSession:(GCKSession *)session {
  NSLog(@"MediaViewController: sessionManager didResumeSession %@", session);
  [self setQueueButtonVisible:YES];
  [self.tableView reloadData];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
         didEndSession:(GCKSession *)session
             withError:(NSError *)error {
  NSLog(@"session ended with error: %@", error);
  NSString *message =
      [NSString stringWithFormat:@"The Casting session has ended.\n%@",
                                 error.description];

  [Toast displayToastMessage:message
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:NO];
  [self.tableView reloadData];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
    didFailToStartSessionWithError:(NSError *)error {
  [self showAlertWithTitle:@"Failed to start a session"
                   message:error.description];
  [self setQueueButtonVisible:NO];
  [self.tableView reloadData];
}

- (void)sessionManager:(GCKSessionManager *)sessionManager
didFailToResumeSession:(GCKSession *)session
             withError:(NSError *)error {
  [Toast displayToastMessage:@"The Casting session could not be resumed."
             forTimeInterval:3
                      inView:[UIApplication sharedApplication].delegate.window];
  [self setQueueButtonVisible:NO];
  [self.tableView reloadData];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil];
  [alert show];
}

#pragma mark - GCKRequestDelegate

- (void)requestDidComplete:(GCKRequest *)request {
  NSLog(@"request %ld completed", (long)request.requestID);
}

- (void)request:(GCKRequest *)request didFailWithError:(GCKError *)error {
  NSLog(@"request %ld failed with error %@", (long)request.requestID, error);
}

@end
