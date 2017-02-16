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
import UIKit
import GoogleCast
let kPrefMediaListURL: String = "media_list_url"

@objc(MediaTableViewController)
class MediaTableViewController: UITableViewController, GCKSessionManagerListener, MediaListModelDelegate, GCKRequestDelegate {
  var sessionManager: GCKSessionManager!
  var castSession: GCKCastSession!
  var rootTitleView: UIImageView!
  var titleView: UIView!
  var mediaListURL: URL!
  var queueButton: UIBarButtonItem!
  var actionSheet: ActionSheet!
  var selectedItem: MediaItem!
  var queueAdded: Bool = false
  var castButton: GCKUICastButton!


  /** The media to be displayed. */
  var mediaList: MediaListModel?
  var rootItem: MediaItem? {
    didSet {
      self.title = rootItem?.title
      self.tableView.reloadData()
    }
  }


  override func viewDidLoad() {
    print("MediaTableViewController - viewDidLoad")
    super.viewDidLoad()
    self.sessionManager = GCKCastContext.sharedInstance().sessionManager
    self.sessionManager.add(self)
    self.titleView = self.navigationItem.titleView
    self.rootTitleView = UIImageView(image: UIImage(named: "logo_castvideos.png"))
    NotificationCenter.default.addObserver(self, selector: #selector(self.loadMediaList), name: UserDefaults.didChangeNotification, object: nil)
    if self.rootItem == nil {
      self.loadMediaList()
    }
    self.castButton = GCKUICastButton(frame: CGRect(x: CGFloat(0), y: CGFloat(0), width: CGFloat(24), height: CGFloat(24)))
    self.castButton.tintColor = UIColor.white
    self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.castButton)
    self.queueButton = UIBarButtonItem(image: UIImage(named: "playlist_white.png"), style: .plain, target: self, action: #selector(self.didTapQueueButton))
    self.tableView.separatorColor = UIColor.clear
    NotificationCenter.default.addObserver(self, selector: #selector(self.deviceOrientationDidChange), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(self, selector: #selector(self.castDeviceDidChange), name: NSNotification.Name.gckCastStateDidChange, object: GCKCastContext.sharedInstance())
  }

  func castDeviceDidChange(_ notification: Notification) {
    if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
      // You can present the instructions on how to use Google Cast on
      // the first time the user uses you app
      GCKCastContext.sharedInstance().presentCastInstructionsViewControllerOnce()
    }
  }

  func deviceOrientationDidChange(_ notification: Notification) {
    self.tableView.reloadData()
  }

  func setQueueButtonVisible(_ visible: Bool) {
    if visible && !self.queueAdded {
      var barItems = (arrayLiteral: self.navigationItem.rightBarButtonItems)
      barItems?.append(self.queueButton)
      self.navigationItem.rightBarButtonItems = barItems
      self.queueAdded = true
    }
    else if !visible && self.queueAdded {
      var barItems = (arrayLiteral: self.navigationItem.rightBarButtonItems)
      barItems?.remove(at: barItems?.index(of: self.queueButton) ?? -1)
      self.navigationItem.rightBarButtonItems = barItems
      self.queueAdded = false
    }

  }

  func didTapQueueButton(_ sender: Any) {
    self.performSegue(withIdentifier: "MediaQueueSegue", sender: self)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    print("viewWillAppear - Table view")
    self.navigationController?.navigationBar.isTranslucent = false
    self.navigationController?.navigationBar.setBackgroundImage(nil, for: .default)
    self.navigationController?.navigationBar.shadowImage = nil
    UIApplication.shared.setStatusBarHidden(false, with: .fade)
    self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    if self.rootItem?.parent == nil {
      // If this is the root group, show stylized application title in the title
      // view.
      self.navigationItem.titleView = self.rootTitleView
    }
    else {
      // Otherwise show the title of the group in the title view.
      self.navigationItem.titleView = self.titleView
      self.title = self.rootItem?.title
    }
    appDelegate?.isCastControlBarsEnabled = true
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  }
  // MARK: - Table View

  override func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if (self.rootItem != nil) {
      return self.rootItem!.items.count
    } else {
      return 0
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "MediaCell")
    let item: MediaItem? = (self.rootItem?.items[indexPath.row] as? MediaItem)
    var detail: String? = nil
    let mediaInfo: GCKMediaInformation? = item?.mediaInfo
    if mediaInfo != nil {
      detail = mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyStudio)
      if detail == nil {
        detail = mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyArtist)
      }
    }
    let mediaTitle = (cell?.viewWithTag(1) as? UILabel)
    let mediaOwner = (cell?.viewWithTag(2) as? UILabel)
      var titleText = item?.title
      var ownerText = detail
      let text = "\(titleText ?? "")\n\(ownerText ?? "")"
      let attribs = [NSForegroundColorAttributeName: mediaTitle?.textColor, NSFontAttributeName: mediaTitle?.font]
      let attributedText = NSMutableAttributedString(string: text, attributes: attribs)
      let blackColor = UIColor.black
      let titleTextRange = NSRange(location: 0, length: (titleText?.characters.count ?? 0))
      attributedText.setAttributes([NSForegroundColorAttributeName: blackColor], range: titleTextRange)
      let lightGrayColor = UIColor.lightGray
      let ownerTextRange = NSRange(location: (titleText?.characters.count ?? 0) + 1, length: (ownerText?.characters.count ?? 0))
      attributedText.setAttributes([NSForegroundColorAttributeName: lightGrayColor, NSFontAttributeName: UIFont.systemFont(ofSize: CGFloat(12))], range: ownerTextRange)
      mediaTitle?.attributedText = attributedText
      mediaOwner?.isHidden = true

    if item?.mediaInfo != nil {
      cell?.accessoryType = .none
    }
    else {
      cell?.accessoryType = .disclosureIndicator
    }
    let imageView: UIImageView? = (cell?.contentView.viewWithTag(3) as? UIImageView)
    GCKCastContext.sharedInstance().imageCache?.fetchImage(for: (item?.imageURL)!, completion: {(_ image: UIImage?) -> Void in
      imageView?.image = image
      cell?.setNeedsLayout()
    })
    let addButton: UIButton? = (cell?.viewWithTag(4) as? UIButton)
    let hasConnectedCastSession: Bool = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
    if hasConnectedCastSession {
      addButton?.isHidden = false
      addButton?.addTarget(self, action: #selector(self.playButtonClicked), for: .touchDown)
    }
    else {
      addButton?.isHidden = true
    }
    return cell!
  }

  @IBAction func playButtonClicked(_ sender: Any) {
    let tableViewCell = ((sender as AnyObject).superview??.superview as? UITableViewCell)
    var indexPathForCell: IndexPath? = self.tableView.indexPath(for: tableViewCell!)
    selectedItem = (self.rootItem?.items[(indexPathForCell?.row)!] as? MediaItem)
    let hasConnectedCastSession: Bool = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
    if (selectedItem.mediaInfo != nil) && hasConnectedCastSession {
      // Display an popover to allow the user to add to queue or play
      // immediately.
      if !(self.actionSheet != nil) {
        self.actionSheet = ActionSheet(title: "Play Item", message: "Select an action", cancelButtonText: "Cancel")
        self.actionSheet.addAction(withTitle: "Play Now", target: self, selector: #selector(self.playSelectedItemRemotely))
        self.actionSheet.addAction(withTitle: "Add to Queue", target: self, selector: #selector(self.enqueueSelectedItemRemotely))
      }
      self.actionSheet.present(in: self, sourceView: tableViewCell!)
    }
  }
  // TODO

  @IBAction func playButtonClickedOld(_ sender: Any) {
    let tableViewCell = (sender as AnyObject).superview??.superview as! UITableViewCell
    var indexPathForCell: IndexPath? = self.tableView.indexPath(for: tableViewCell)
    selectedItem = (self.rootItem?.items[(indexPathForCell?.row)!] as? MediaItem)
    let isHasConnectedCastSession: Bool = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
    if (selectedItem.mediaInfo != nil) && isHasConnectedCastSession {
      // Display an alert box to allow the user to add to queue or play
      // immediately.
      if (self.actionSheet == nil) {
        self.actionSheet = ActionSheet(title: "Play Item", message: "Select an action", cancelButtonText: "Cancel")
        self.actionSheet.addAction(withTitle: "Play Now", target: self, selector: #selector(self.playSelectedItemRemotely))
        self.actionSheet.addAction(withTitle: "Add to Queue", target: self, selector: #selector(self.enqueueSelectedItemRemotely))
      }
      self.actionSheet.present(in: self, sourceView: tableViewCell)
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if let item = self.rootItem?.items[indexPath.row] as? MediaItem, let _ = item.mediaInfo {
      self.performSegue(withIdentifier: "mediaDetails", sender: self)
    }
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    print("prepareForSegue")
    if (segue.identifier == "mediaDetails") {
      let viewController: MediaViewController? = (segue.destination as? MediaViewController)
      let mediaInfo: GCKMediaInformation? = self.getSelectedItem().mediaInfo
      if mediaInfo != nil {
        viewController?.mediaInfo = mediaInfo
      }
    }
  }

  func playSelectedItemRemotely() {
    self.loadSelectedItem(byAppending: false)
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }

  func enqueueSelectedItemRemotely() {
    self.loadSelectedItem(byAppending: true)
    // selectedItem = [self getSelectedItem];
    let message = "Added \"\(selectedItem.mediaInfo.metadata?.string(forKey: kGCKMetadataKeyTitle))\" to queue."
    Toast.displayMessage(message, for: 3, in: appDelegate?.window)
    self.setQueueButtonVisible(true)
  }
  /**
   * Loads the currently selected item in the current cast media session.
   * @param appending If YES, the item is appended to the current queue if there
   * is one. If NO, or if
   * there is no queue, a new queue containing only the selected item is created.
   */

  func loadSelectedItem(byAppending appending: Bool) {
    print("enqueue item \(selectedItem.mediaInfo)")
    if let castSession = GCKCastContext.sharedInstance().sessionManager.currentSession as? GCKCastSession {
      if ((castSession.remoteMediaClient) != nil) {
        let builder = GCKMediaQueueItemBuilder()
        builder.mediaInformation = selectedItem.mediaInfo
        builder.autoplay = true
        builder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
        let item = builder.build()
        if ((castSession.remoteMediaClient?.mediaStatus) != nil) && appending {
          let request: GCKRequest? = castSession.remoteMediaClient?.queueInsert(item, beforeItemWithID: kGCKMediaQueueInvalidItemID)
          request?.delegate = self
        }
        else {
          let repeatMode = (castSession.remoteMediaClient?.mediaStatus != nil) ? castSession.remoteMediaClient?.mediaStatus?.queueRepeatMode : .off
          let request = castSession.remoteMediaClient?.queueLoad([item], start: 0, playPosition: 0, repeatMode: repeatMode!, customData: nil)
          request?.delegate = self
        }
      }
    }
  }

  func getSelectedItem() -> MediaItem {
    var item: MediaItem? = nil
    var indexPath: IndexPath? = self.tableView.indexPathForSelectedRow
    if indexPath != nil {
      print("selected row is \(indexPath)")
      item = (self.rootItem?.items[(indexPath?.row)!] as? MediaItem)
    }
    return item!
  }
  // MARK: - MediaListModelDelegate

  func mediaListModelDidLoad(_ list: MediaListModel) {
    self.rootItem = self.mediaList?.rootItem
    self.title = self.mediaList?.title
    self.tableView.reloadData()
  }

  func mediaListModel(_ list: MediaListModel, didFailToLoadWithError error: Error?) {
    let errorMessage: String = "Unable to load the media list from\n\(self.mediaListURL.absoluteString)."
    let alert = UIAlertView(title: NSLocalizedString("Cast Error", comment: ""), message: NSLocalizedString(errorMessage, comment: ""), delegate: nil, cancelButtonTitle: NSLocalizedString("OK", comment: ""), otherButtonTitles: "")
    alert.show()
  }

  func loadMediaList() {
    // Look up the media list URL.
    let userDefaults = UserDefaults.standard
    let urlKey: String? = userDefaults.string(forKey: kPrefMediaListURL)
    let urlText: String? = userDefaults.string(forKey: urlKey!)
    let mediaListURL = URL(string: urlText!)
    if (self.mediaListURL != nil) && (mediaListURL == self.mediaListURL) {
      // The URL hasn't changed; do nothing.
      return
    }
    self.mediaListURL = mediaListURL
    // Asynchronously load the media json.
    let delegate: AppDelegate? = (UIApplication.shared.delegate as? AppDelegate)
    delegate?.mediaList = MediaListModel()
    self.mediaList = delegate?.mediaList
    self.mediaList?.delegate = self
    self.mediaList?.load(from: self.mediaListURL)
  }
  // MARK: - GCKSessionManagerListener

  func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
    print("MediaViewController: sessionManager didStartSession \(session)")
    self.setQueueButtonVisible(true)
    self.tableView.reloadData()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
    print("MediaViewController: sessionManager didResumeSession \(session)")
    self.setQueueButtonVisible(true)
    self.tableView.reloadData()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    print("session ended with error: \(error)")
    let message = "The Casting session has ended.\n\((error as! NSError).description)"
    if let window = appDelegate?.window {
      Toast.displayMessage(message, for: 3, in: window)
    }
    self.setQueueButtonVisible(false)
    self.tableView.reloadData()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
    self.showAlert(withTitle: "Failed to start a session", message: (error as! NSError).description)
    self.setQueueButtonVisible(false)
    self.tableView.reloadData()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToResumeSession session: GCKSession, withError error: Error?) {
    Toast.displayMessage("The Casting session could not be resumed.", for: 3, in: (UIApplication.shared.delegate?.window)!)
    self.setQueueButtonVisible(false)
    self.tableView.reloadData()
  }

  func showAlert(withTitle title: String, message: String) {
    let alert = UIAlertView(title: title, message: message, delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
    alert.show()
  }
  // MARK: - GCKRequestDelegate

  func requestDidComplete(_ request: GCKRequest) {
    print("request \(Int(request.requestID)) completed")
  }

  func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    print("request \(Int(request.requestID)) failed with error \(error)")
  }
}
