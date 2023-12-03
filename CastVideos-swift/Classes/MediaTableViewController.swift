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

import GoogleCast
import UIKit

let kPrefMediaListURL: String = "media_list_url"

@objc(MediaTableViewController)
class MediaTableViewController: UITableViewController, GCKSessionManagerListener, MediaListModelDelegate, GCKRequestDelegate {
  private var sessionManager: GCKSessionManager!
  private var rootTitleView: UIImageView!
  private var titleView: UIView!
  private var mediaListURL: URL!
  private var queueButton: UIBarButtonItem!
  private var actionSheet: ActionSheet!
  private var selectedItem: MediaItem!
  private var queueAdded: Bool = false
  private var castButton: GCKUICastButton!
  private var credentials: String? = nil
    
  /** The media to be displayed. */
  var mediaList: MediaListModel?
  var rootItem: MediaItem? {
    didSet {
      title = rootItem?.title
      tableView.reloadData()
    }
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    sessionManager = GCKCastContext.sharedInstance().sessionManager
  }

  override func viewDidLoad() {
    print("MediaTableViewController - viewDidLoad")
    super.viewDidLoad()
    sessionManager.add(self)
    titleView = navigationItem.titleView
    rootTitleView = UIImageView(image: UIImage(named: "logo_castvideos.png"))
    NotificationCenter.default.addObserver(self, selector: #selector(loadMediaList),
                                           name: UserDefaults.didChangeNotification, object: nil)
    if rootItem == nil {
      loadMediaList()
    }
    castButton = GCKUICastButton(frame: CGRect(x: CGFloat(0), y: CGFloat(0),
                                               width: CGFloat(24), height: CGFloat(24)))
    // Overwrite the UIAppearance theme in the AppDelegate.
    castButton.tintColor = UIColor.white
    navigationItem.rightBarButtonItem = UIBarButtonItem(customView: castButton)
    queueButton = UIBarButtonItem(image: UIImage(named: "playlist_white.png"),
                                  style: .plain, target: self, action: #selector(didTapQueueButton))
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Creds", style: .plain,
                                                       target: self, action: #selector(toggleLaunchCreds))
    tableView.separatorColor = UIColor.clear
    NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange),
                                           name: UIDevice.orientationDidChangeNotification, object: nil)
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(self, selector: #selector(castDeviceDidChange),
                                           name: NSNotification.Name.gckCastStateDidChange,
                                           object: GCKCastContext.sharedInstance())
    setLaunchCreds()
  }

  @objc func toggleLaunchCreds(_: Any){
    if (credentials == nil) {
        credentials = "{\"userId\":\"id123\"}"
    } else {
        credentials = nil
    }
    Toast.displayMessage("Launch Credentials: "+(credentials ?? "Null"), for: 3, in: appDelegate?.window)
    print("Credentials set: "+(credentials ?? "Null"))
    setLaunchCreds()
  }

  @objc func castDeviceDidChange(_: Notification) {
    if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
      // You can present the instructions on how to use Google Cast on
      // the first time the user uses you app
      GCKCastContext.sharedInstance().presentCastInstructionsViewControllerOnce(with: castButton)
    }
  }

  @objc func deviceOrientationDidChange(_: Notification) {
    tableView.reloadData()
  }

  func setQueueButtonVisible(_ visible: Bool) {
    if visible, !queueAdded {
      var barItems = navigationItem.rightBarButtonItems
      barItems?.append(queueButton)
      navigationItem.rightBarButtonItems = barItems
      queueAdded = true
    } else if !visible, queueAdded {
      var barItems = navigationItem.rightBarButtonItems
      let index = barItems?.firstIndex(of: queueButton) ?? -1
      barItems?.remove(at: index)
      navigationItem.rightBarButtonItems = barItems
      queueAdded = false
    }
  }

  @objc func didTapQueueButton(_: Any) {
    performSegue(withIdentifier: "MediaQueueSegue", sender: self)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    print("viewWillAppear - Table view")
    navigationController?.navigationBar.isTranslucent = false
    navigationController?.navigationBar.setBackgroundImage(nil, for: .default)
    navigationController?.navigationBar.shadowImage = nil
    navigationController?.interactivePopGestureRecognizer?.isEnabled = true

    // Fix navigationBar color for iOS 15+
    if #available(iOS 15.0, *) {
      let navigationBarAppearance = UINavigationBarAppearance()
      navigationBarAppearance.backgroundColor = navigationController?.navigationBar.barTintColor
      navigationController?.navigationBar.standardAppearance = navigationBarAppearance
      navigationController?.navigationBar.scrollEdgeAppearance = navigationBarAppearance
    }

    if rootItem?.parent == nil {
      // If this is the root group, show stylized application title in the title view.
      navigationItem.titleView = rootTitleView
    } else {
      // Otherwise show the title of the group in the title view.
      navigationItem.titleView = titleView
      title = rootItem?.title
    }
    appDelegate?.isCastControlBarsEnabled = true
  }

  // MARK: - Table View

  override func numberOfSections(in _: UITableView) -> Int {
    return 1
  }

  override func tableView(_: UITableView,
                          numberOfRowsInSection _: Int) -> Int {
    if let rootItem = rootItem {
      return rootItem.children.count
    } else {
      return 0
    }
  }

  override func tableView(_ tableView: UITableView,
                          cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "MediaCell",
                                             for: indexPath)
    guard let item = rootItem?.children[indexPath.row] as? MediaItem else { return cell }
    var detail: String?
    if let mediaInfo = item.mediaInfo {
      detail = mediaInfo.metadata?.string(forKey: kGCKMetadataKeyStudio)
      if detail == nil {
        detail = mediaInfo.metadata?.string(forKey: kGCKMetadataKeyArtist)
      }
    }
    if let mediaTitle = (cell.viewWithTag(1) as? UILabel) {
      let titleText = item.title
      let ownerText = detail
      let text = "\(titleText ?? "")\n\(ownerText ?? "")"

      let attribs = [NSAttributedString.Key.foregroundColor: mediaTitle.textColor as Any,
                     NSAttributedString.Key.font: mediaTitle.font as Any] as [NSAttributedString.Key: Any]
      let attributedText = NSMutableAttributedString(string: text, attributes: attribs)
      let titleColor: UIColor!
      let subtitleColor: UIColor!

      if #available(iOS 13.0, *) {
        titleColor = UIColor.label
        subtitleColor = UIColor.secondaryLabel
      } else {
        titleColor = UIColor.black
        subtitleColor = UIColor.lightGray
      }

      let titleTextRange = NSRange(location: 0, length: (titleText?.count ?? 0))
      attributedText.setAttributes([NSAttributedString.Key.foregroundColor: titleColor as Any], range: titleTextRange)
      let ownerTextRange = NSRange(location: (titleText?.count ?? 0) + 1,
                                   length: (ownerText?.count ?? 0))
      attributedText.setAttributes([NSAttributedString.Key.foregroundColor: subtitleColor as Any,
                                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: CGFloat(12))], range: ownerTextRange)
      mediaTitle.attributedText = attributedText
    }
    let mediaOwner = (cell.viewWithTag(2) as? UILabel)
    mediaOwner?.isHidden = true

    if item.mediaInfo != nil {
      cell.accessoryType = .none
    } else {
      cell.accessoryType = .disclosureIndicator
    }
    if let imageView = (cell.contentView.viewWithTag(3) as? UIImageView), let imageURL = item.imageURL {
      GCKCastContext.sharedInstance().imageCache?.fetchImage(for: imageURL, completion: { (_ image: UIImage?) -> Void in
        imageView.image = image
        cell.setNeedsLayout()
      })
    }
    let addButton: UIButton? = (cell.viewWithTag(4) as? UIButton)
    let hasConnectedCastSession: Bool = sessionManager.hasConnectedCastSession()
    if hasConnectedCastSession {
      addButton?.isHidden = false
      addButton?.addTarget(self, action: #selector(playButtonClicked), for: .touchDown)
    } else {
      addButton?.isHidden = true
    }
    return cell
  }

  @IBAction func playButtonClicked(_ sender: Any) {
    guard let tableViewCell = (sender as AnyObject).superview??.superview as? UITableViewCell else { return }
    guard let indexPathForCell = tableView.indexPath(for: tableViewCell) else { return }
    selectedItem = (rootItem?.children[indexPathForCell.row] as? MediaItem)
    let hasConnectedCastSession: Bool = sessionManager.hasConnectedCastSession()
    if selectedItem.mediaInfo != nil, hasConnectedCastSession {
      // Display an popover to allow the user to add to queue or play
      // immediately.
      if actionSheet == nil {
        actionSheet = ActionSheet(title: "Play Item", message: "Select an action", cancelButtonText: "Cancel")
        actionSheet.addAction(withTitle: "Play Now", target: self,
                              selector: #selector(playSelectedItemRemotely))
        actionSheet.addAction(withTitle: "Add to Queue", target: self,
                              selector: #selector(enqueueSelectedItemRemotely))
      }
      actionSheet.present(in: self, sourceView: tableViewCell)
    }
  }

  override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    if let item = rootItem?.children[indexPath.row] as? MediaItem, item.mediaInfo != nil {
      performSegue(withIdentifier: "mediaDetails", sender: self)
    }
  }

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    print("prepareForSegue")
    if segue.identifier == "mediaDetails" {
      let viewController: MediaViewController? = (segue.destination as? MediaViewController)
      if let mediaInfo = getSelectedItem()?.mediaInfo {
        viewController?.mediaInfo = mediaInfo
      }
    }
  }

  @objc func playSelectedItemRemotely() {
    loadSelectedItem(byAppending: false)
    appDelegate?.isCastControlBarsEnabled = false
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }

  @objc func enqueueSelectedItemRemotely() {
    loadSelectedItem(byAppending: true)
    // selectedItem = [self getSelectedItem];
    let message = "Added \"\(selectedItem.mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyTitle) ?? "")\" to queue."
    Toast.displayMessage(message, for: 3, in: appDelegate?.window)
    setQueueButtonVisible(true)
  }

  /**
   * Loads the currently selected item in the current cast media session.
   * @param appending If YES, the item is appended to the current queue if there
   * is one. If NO, or if
   * there is no queue, a new queue containing only the selected item is created.
   */
  func loadSelectedItem(byAppending appending: Bool) {
    print("enqueue item \(String(describing: selectedItem.mediaInfo))")
    if let remoteMediaClient = sessionManager.currentCastSession?.remoteMediaClient {
      let mediaQueueItemBuilder = GCKMediaQueueItemBuilder()
      mediaQueueItemBuilder.mediaInformation = selectedItem.mediaInfo
      mediaQueueItemBuilder.autoplay = true
      mediaQueueItemBuilder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
      let mediaQueueItem: GCKMediaQueueItem = mediaQueueItemBuilder.build()!
      if appending {
        let request = remoteMediaClient.queueInsert(mediaQueueItem, beforeItemWithID: kGCKMediaQueueInvalidItemID)
        request.delegate = self
      } else {
        let queueDataBuilder = GCKMediaQueueDataBuilder(queueType: .generic)
        queueDataBuilder.items = [mediaQueueItem]
        queueDataBuilder.repeatMode = remoteMediaClient.mediaStatus?.queueRepeatMode ?? .off

        let mediaLoadRequestDataBuilder = GCKMediaLoadRequestDataBuilder()
        mediaLoadRequestDataBuilder.queueData = queueDataBuilder.build()
        mediaLoadRequestDataBuilder.credentials = credentials

        let request = remoteMediaClient.loadMedia(with: mediaLoadRequestDataBuilder.build())
        request.delegate = self
      }
    }
  }

  func getSelectedItem() -> MediaItem? {
    guard let indexPath = tableView.indexPathForSelectedRow else { return nil }
    print("selected row is \(indexPath)")
    return (rootItem?.children[(indexPath.row)] as? MediaItem)
  }

  // MARK: - MediaListModelDelegate

  func mediaListModelDidLoad(_: MediaListModel) {
    rootItem = mediaList?.rootItem
    title = mediaList?.title
    tableView.reloadData()
  }

  func mediaListModel(_: MediaListModel, didFailToLoadWithError _: Error?) {
    let errorMessage: String = "Unable to load the media list from\n\(mediaListURL.absoluteString)."
    let alertController = UIAlertController(title: "Cast Error",
                                            message: errorMessage,
                                            preferredStyle: UIAlertController.Style.alert)
    let action = UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil)
    alertController.addAction(action)

    present(alertController, animated: true, completion: nil)
  }

  @objc func loadMediaList() {
    // Look up the media list URL.
    let userDefaults = UserDefaults.standard
    guard let urlKey = userDefaults.string(forKey: kPrefMediaListURL) else { return }
    guard let urlText = userDefaults.string(forKey: urlKey) else { return }
    let _mediaListURL = URL(string: urlText)
    if mediaListURL == _mediaListURL {
      // The URL hasn't changed; do nothing.
      return
    }
    mediaListURL = _mediaListURL
    print("Media list URL: \(String(describing: mediaListURL))")
    // Asynchronously load the media json.
    mediaList = MediaListModel()
    mediaList?.delegate = self
    mediaList?.load(from: mediaListURL)
  }

  // MARK: - GCKSessionManagerListener

  func sessionManager(_: GCKSessionManager, didStart session: GCKSession) {
    print("MediaViewController: sessionManager didStartSession \(session)")
    setQueueButtonVisible(true)
    tableView.reloadData()
  }

  func sessionManager(_: GCKSessionManager, didResumeSession session: GCKSession) {
    print("MediaViewController: sessionManager didResumeSession \(session)")
    setQueueButtonVisible(true)
    tableView.reloadData()
  }

  func sessionManager(_: GCKSessionManager, didEnd _: GCKSession, withError error: Error?) {
    print("session ended with error: \(String(describing: error))")
    let message = "The Casting session has ended.\n\(String(describing: error))"
    if let window = appDelegate?.window {
      Toast.displayMessage(message, for: 3, in: window)
    }
    setQueueButtonVisible(false)
    tableView.reloadData()
  }

  func sessionManager(_: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
    if let error = error {
      showAlert(withTitle: "Failed to start a session", message: error.localizedDescription)
    }
    setQueueButtonVisible(false)
    tableView.reloadData()
  }

  func sessionManager(_: GCKSessionManager,
                      didFailToResumeSession _: GCKSession, withError _: Error?) {
    if let window = UIApplication.shared.delegate?.window {
      Toast.displayMessage("The Casting session could not be resumed.", for: 3, in: window)
    }
    setQueueButtonVisible(false)
    tableView.reloadData()
  }

  func showAlert(withTitle title: String, message: String) {
    let alertController = UIAlertController(title: title,
                                            message: message,
                                            preferredStyle: UIAlertController.Style.alert)
    let action = UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil)
    alertController.addAction(action)

    present(alertController, animated: true, completion: nil)
  }

  // MARK: - GCKRequestDelegate

  func requestDidComplete(_ request: GCKRequest) {
    print("request \(Int(request.requestID)) completed")
  }

  func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    print("request \(Int(request.requestID)) failed with error \(error)")
  }
  
  func setLaunchCreds() {
    GCKCastContext.sharedInstance()
        .setLaunch(GCKCredentialsData(credentials: credentials))
  }
}
