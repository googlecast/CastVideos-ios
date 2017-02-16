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
class MediaQueueViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, GCKSessionManagerListener, GCKRemoteMediaClientListener, GCKRequestDelegate {


  var timer: Timer!
  // Queue
  @IBOutlet var tableView: UITableView!
  // Queue/editing state.
  @IBOutlet var editButton: UIBarButtonItem!
  var _editing: Bool = false
  var mediaClient: GCKRemoteMediaClient!
  var mediaController: GCKUIMediaController!
  var queueRequest: GCKRequest!


  override func viewDidLoad() {
    print("_tableView is \(self.tableView)")
    self.tableView.dataSource = self
    self.tableView.delegate = self
    self.isEditing = false
    let sessionManager = GCKCastContext.sharedInstance().sessionManager
    sessionManager.add(self)
    if sessionManager.hasConnectedCastSession() {
      self.attach(to: sessionManager.currentCastSession!)
    }
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress))
    recognizer.minimumPressDuration = 2.0
    // 2 seconds
    self.tableView.addGestureRecognizer(recognizer)
    self.tableView.separatorColor = UIColor.clear
    super.viewDidLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    appDelegate?.isCastControlBarsEnabled = false
    super.viewWillAppear(animated)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.queueRequest = nil
    self.tableView.isUserInteractionEnabled = true
    if self.mediaClient.mediaStatus?.queueItemCount() == 0 {
      self.editButton.isEnabled = false
    }
    else {
      self.editButton.isEnabled = true
    }
    self.tableView.reloadData()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
  }
  // MARK: - UI Actions

  @IBAction func toggleEditing(_ sender: Any) {
    if self.isEditing {
      self.editButton.title = "Edit"
      self.tableView.setEditing(false, animated: true)
      self.isEditing = false
      if self.mediaClient.mediaStatus?.queueItemCount() == 0 {
        self.editButton.isEnabled = false
      }
    }
    else {
      self.editButton.title = "Done"
      self.tableView.setEditing(true, animated: true)
      self.isEditing = true
    }
  }

  func showErrorMessage(_ message: String) {
    let alert = UIAlertView(title: NSLocalizedString("Error", comment: ""), message: message, delegate: nil, cancelButtonTitle: NSLocalizedString("OK", comment: ""), otherButtonTitles: "")
    alert.show()
  }

  func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
    var point: CGPoint = gestureRecognizer.location(in: self.tableView)
    var indexPath: IndexPath? = self.tableView.indexPathForRow(at: point)
    if let indexPath = indexPath {
      var item: GCKMediaQueueItem? = self.mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
      if item != nil {
        self.start(self.mediaClient.queueJumpToItem(withID: (item?.itemID)!))
      }
    }
  }
  // MARK: - UITableViewDataSource

  func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if (self.mediaClient == nil) || (self.mediaClient.mediaStatus == nil) {
      return 0
    }
    return Int(self.mediaClient.mediaStatus!.queueItemCount())
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "MediaCell")
    var item: GCKMediaQueueItem? = self.mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
    var title: String? = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyTitle)
    var artist: String? = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyArtist)
    if artist == nil {
      artist = item?.mediaInformation.metadata?.string(forKey: kGCKMetadataKeyStudio)
    }
    var detail: String? = "(\(GCKUIUtils.timeInterval(asString: (item?.mediaInformation.streamDuration)!))) \(artist)"
    var mediaTitle: UILabel? = (cell?.viewWithTag(1) as? UILabel)
    mediaTitle?.text = title
    var mediaOwner: UILabel? = (cell?.viewWithTag(2) as? UILabel)
    mediaOwner?.text = detail
    if self.mediaClient.mediaStatus?.currentItemID == item?.itemID {
      cell?.backgroundColor = UIColor(red: CGFloat(15.0 / 255), green: CGFloat(153.0 / 255), blue: CGFloat(242.0 / 255), alpha: CGFloat(0.1))
    }
    else {
      cell?.backgroundColor = nil
    }
    let imageView = (cell?.contentView.viewWithTag(3) as? UIImageView)
    if let images = item?.mediaInformation.metadata?.images(), images.count > 0 {
      let image = images[0] as? GCKImage
      GCKCastContext.sharedInstance().imageCache?.fetchImage(for: (image?.url)!, completion: {(_ image: UIImage?) -> Void in
        imageView?.image = image
        cell?.setNeedsLayout()
      })
    }
    return cell!
  }
  // MARK: - UITableViewDelegate

  func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    return true
  }

  func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    if sourceIndexPath.row == destinationIndexPath.row {
      return
    }
    let sourceItem = self.mediaClient.mediaStatus?.queueItem(at: UInt(sourceIndexPath.row))
    var insertBeforeID = kGCKMediaQueueInvalidItemID
    if destinationIndexPath.row < Int((self.mediaClient.mediaStatus?.queueItemCount())!) - 1 {
      let beforeItem: GCKMediaQueueItem? = self.mediaClient.mediaStatus?.queueItem(at: UInt(destinationIndexPath.row))
      insertBeforeID = (beforeItem?.itemID)!
    }
    self.start(self.mediaClient.queueMoveItem(withID: (sourceItem?.itemID)!, beforeItemWithID: insertBeforeID))
  }

  func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
    return .delete
  }

  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      // Delete row.
      let item: GCKMediaQueueItem? = self.mediaClient.mediaStatus?.queueItem(at: UInt(indexPath.row))
      if item != nil {
        self.start(self.mediaClient.queueRemoveItem(withID: (item?.itemID)!))
      }
    }
  }

  func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
    // No-op.
  }
  // MARK: - Session handling

  func attach(to castSession: GCKCastSession) {
    self.mediaClient = castSession.remoteMediaClient
    self.mediaClient.add(self)
    self.tableView.reloadData()
  }

  func detachFromCastSession() {
    self.mediaClient.remove(self)
    self.mediaClient = nil
    self.tableView.reloadData()
  }
  // MARK: - GCKSessionManagerListener

  func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
    self.attach(to: session)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didSuspend session: GCKCastSession, with reason: GCKConnectionSuspendReason) {
    self.detachFromCastSession()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
    self.attach(to: session)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, willEnd session: GCKCastSession) {
    self.detachFromCastSession()
  }
  // MARK: - GCKRemoteMediaClientListener

  func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus) {
    self.tableView.reloadData()
  }

  func remoteMediaClientDidUpdateQueue(_ client: GCKRemoteMediaClient) {
    self.tableView.reloadData()
  }
  // MARK: - Request scheduling

  func start(_ request: GCKRequest) {
    self.queueRequest = request
    self.queueRequest.delegate = self
    self.tableView.isUserInteractionEnabled = false
  }
  // MARK: - GCKRequestDelegate

  func requestDidComplete(_ request: GCKRequest) {
    if request == self.queueRequest {
      self.queueRequest = nil
      self.tableView.isUserInteractionEnabled = true
    }
  }

  func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    if request == self.queueRequest {
      self.queueRequest = nil
      self.tableView.isUserInteractionEnabled = true
      self.showErrorMessage("Queue request failed:\n\(error.description)")
    }
  }

  func requestWasReplaced(_ request: GCKRequest) {
    if request == self.queueRequest {
      self.queueRequest = nil
      self.tableView.isUserInteractionEnabled = true
    }
  }
}
