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

import GoogleCast
import UIKit

@objc(MediaQueueViewController)
class MediaQueueViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
  GCKSessionManagerListener, GCKRemoteMediaClientListener, GCKRequestDelegate {
  private var timer: Timer!
  // Queue
  @IBOutlet private var _tableView: UITableView!
  // Queue/editing state.
  @IBOutlet private var _editButton: UIBarButtonItem!
  private var _editing = false
  private var mediaClient: GCKRemoteMediaClient!
  private var mediaController: GCKUIMediaController!
  private var queueRequest: GCKRequest!

  override func viewDidLoad() {
    print("_tableView is \(_tableView.description)")
    _tableView.dataSource = self
    _tableView.delegate = self
    _editing = false
    let sessionManager = GCKCastContext.sharedInstance().sessionManager
    sessionManager.add(self)
    if sessionManager.hasConnectedCastSession() {
      attach(to: sessionManager.currentCastSession!)
    }
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    recognizer.minimumPressDuration = 2.0
    // 2 seconds
    _tableView.addGestureRecognizer(recognizer)
    _tableView.separatorColor = UIColor.clear
    super.viewDidLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    appDelegate?.isCastControlBarsEnabled = false
    super.viewWillAppear(animated)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    queueRequest = nil
    _tableView.isUserInteractionEnabled = true
    if mediaClient.mediaStatus?.queueItemCount == 0 {
      _editButton.isEnabled = false
    } else {
      _editButton.isEnabled = true
    }
    _tableView.reloadData()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
  }

  // MARK: - UI Actions

  @IBAction func toggleEditing(_: Any) {
    if _editing {
      _editButton.title = "Edit"
      _tableView.setEditing(false, animated: true)
      _editing = false
      if mediaClient.mediaStatus?.queueItemCount == 0 {
        _editButton.isEnabled = false
      }
    } else {
      _editButton.title = "Done"
      _tableView.setEditing(true, animated: true)
      _editing = true
    }
  }

  func showErrorMessage(_ message: String) {
    let alert = UIAlertView(title: NSLocalizedString("Error", comment: ""),
                            message: message,
                            delegate: nil,
                            cancelButtonTitle: NSLocalizedString("OK", comment: ""),
                            otherButtonTitles: "")
    alert.show()
  }

  @objc func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
    let point: CGPoint = gestureRecognizer.location(in: _tableView)
    if let indexPath = _tableView.indexPathForRow(at: point) {
      let item: GCKMediaQueueItem? = mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
      if item != nil {
        start(mediaClient.queueJumpToItem(withID: (item?.itemID)!))
      }
    }
  }

  // MARK: - UITableViewDataSource

  func numberOfSections(in _: UITableView) -> Int {
    return 1
  }

  func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
    if (mediaClient == nil) || (mediaClient.mediaStatus == nil) {
      return 0
    }
    return Int(mediaClient.mediaStatus!.queueItemCount)
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "MediaCell")
    let item: GCKMediaQueueItem? = mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
    let title: String? = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyTitle)
    var artist: String? = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyArtist)
    if artist == nil {
      artist = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyStudio)
    }
    let detail: String? = "(\(GCKUIUtils.timeInterval(asString: (item?.mediaInformation.streamDuration)!))) \(artist ?? "")"
    let mediaTitle: UILabel? = (cell?.viewWithTag(1) as? UILabel)
    mediaTitle?.text = title
    let mediaOwner: UILabel? = (cell?.viewWithTag(2) as? UILabel)
    mediaOwner?.text = detail
    if mediaClient.mediaStatus?.currentItemID == item?.itemID {
      cell?.backgroundColor = UIColor(red: CGFloat(15.0 / 255), green: CGFloat(153.0 / 255),
                                      blue: CGFloat(242.0 / 255), alpha: CGFloat(0.1))
    } else {
      cell?.backgroundColor = nil
    }
    let imageView = (cell?.contentView.viewWithTag(3) as? UIImageView)
    if let images = item?.mediaInformation.metadata?.images(), images.count > 0 {
      let image = images[0] as? GCKImage
      GCKCastContext.sharedInstance().imageCache?.fetchImage(for: (image?.url)!,
                                                             completion: { (_ image: UIImage?) -> Void in
                                                               imageView?.image = image
                                                               cell?.setNeedsLayout()
      })
    }
    return cell!
  }

  // MARK: - UITableViewDelegate

  func tableView(_: UITableView, canMoveRowAt _: IndexPath) -> Bool {
    return true
  }

  func tableView(_: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    if sourceIndexPath.row == destinationIndexPath.row {
      return
    }
    let sourceItem = mediaClient.mediaStatus?.queueItem(at: UInt(sourceIndexPath.row))
    var insertBeforeID = kGCKMediaQueueInvalidItemID
    if destinationIndexPath.row < Int((mediaClient.mediaStatus?.queueItemCount)!) - 1 {
      let beforeItem: GCKMediaQueueItem? = mediaClient.mediaStatus?.queueItem(at: UInt(destinationIndexPath.row))
      insertBeforeID = (beforeItem?.itemID)!
    }
    start(mediaClient.queueMoveItem(withID: (sourceItem?.itemID)!, beforeItemWithID: insertBeforeID))
  }

  func tableView(_: UITableView, editingStyleForRowAt _: IndexPath) -> UITableViewCell.EditingStyle {
    return .delete
  }

  func tableView(_: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                 forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      // Delete row.
      let item: GCKMediaQueueItem? = mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
      if item != nil {
        start(mediaClient.queueRemoveItem(withID: (item?.itemID)!))
      }
    }
  }

  func tableView(_: UITableView, didEndEditingRowAt _: IndexPath?) {}

  // MARK: - Session handling

  func attach(to castSession: GCKCastSession) {
    mediaClient = castSession.remoteMediaClient
    mediaClient.add(self)
    _tableView.reloadData()
  }

  func detachFromCastSession() {
    mediaClient.remove(self)
    mediaClient = nil
    _tableView.reloadData()
  }

  // MARK: - GCKSessionManagerListener

  func sessionManager(_: GCKSessionManager, didStart session: GCKCastSession) {
    attach(to: session)
  }

  func sessionManager(_: GCKSessionManager, didSuspend _: GCKCastSession,
                      with _: GCKConnectionSuspendReason) {
    detachFromCastSession()
  }

  func sessionManager(_: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
    attach(to: session)
  }

  func sessionManager(_: GCKSessionManager, willEnd _: GCKCastSession) {
    detachFromCastSession()
  }

  // MARK: - GCKRemoteMediaClientListener

  func remoteMediaClient(_: GCKRemoteMediaClient, didUpdate _: GCKMediaStatus?) {
    _tableView.reloadData()
  }

  func remoteMediaClientDidUpdateQueue(_: GCKRemoteMediaClient) {
    _tableView.reloadData()
  }

  // MARK: - Request scheduling

  func start(_ request: GCKRequest) {
    queueRequest = request
    queueRequest.delegate = self
    _tableView.isUserInteractionEnabled = false
  }

  // MARK: - GCKRequestDelegate

  func requestDidComplete(_ request: GCKRequest) {
    if request == queueRequest {
      queueRequest = nil
      _tableView.isUserInteractionEnabled = true
    }
  }

  func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    if request == queueRequest {
      queueRequest = nil
      _tableView.isUserInteractionEnabled = true
      showErrorMessage("Queue request failed:\n\(error.description)")
    }
  }

  func requestWasReplaced(_ request: GCKRequest) {
    if request == queueRequest {
      queueRequest = nil
      _tableView.isUserInteractionEnabled = true
    }
  }
}
