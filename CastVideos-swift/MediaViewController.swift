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
/* The player state. */
enum PlaybackMode : Int {
  case none = 0
  case local
  case remote
}

let kPrefShowStreamTimeRemaining: String = "show_stream_time_remaining"


class MediaViewController: UIViewController, GCKSessionManagerListener, GCKRemoteMediaClientListener, LocalPlayerViewDelegate, GCKRequestDelegate {


  @IBOutlet var titleLabel: UILabel!
  @IBOutlet var subtitleLabel: UILabel!
  @IBOutlet var descriptionTextView: UITextView!
  @IBOutlet var localPlayerView: LocalPlayerView!
  var sessionManager: GCKSessionManager!
  var castSession: GCKCastSession!
  var castMediaController: GCKUIMediaController!
  var volumeController: GCKUIDeviceVolumeController!
  var streamPositionSliderMoving: Bool = false
  var playbackMode: PlaybackMode
  var queueButton: UIBarButtonItem!
  var showStreamTimeRemaining: Bool = false
  var localPlaybackImplicitlyPaused: Bool = false
  var actionSheet: ActionSheet!
  var queueAdded: Bool = false
  var gradient: CAGradientLayer!
  var castButton: GCKUICastButton!
  /* Whether to reset the edges on disappearing. */
  var isResetEdgesOnDisappear: Bool = false
  // The media to play.
  var mediaInfo: GCKMediaInformation! {
    get {
      // TODO: add getter implementation
    }
    set(mediaInfo) {
      print("setMediaInfo")
      if mediaInfo != nil {
        self.mediaInfo = mediaInfo
      }
    }
  }


  required init?(coder: NSCoder) {
    super.init(coder: coder)

    self.sessionManager = GCKCastContext.sharedInstance().sessionManager
    self.castMediaController = GCKUIMediaController()
    self.volumeController = GCKUIDeviceVolumeController()

  }

  override func viewDidLoad() {
    super.viewDidLoad()
    print("in MediaViewController viewDidLoad")
    self.localPlayerView.delegate = self
    self.castButton = GCKUICastButton(frame: CGRect(x: CGFloat(0), y: CGFloat(0), width: CGFloat(24), height: CGFloat(24)))
    self.castButton.tintColor = UIColor.white
    self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.castButton)
    self.playbackMode = .none
    self.queueButton = UIBarButtonItem(image: UIImage(named: "playlist_white.png"), style: .plain, target: self, action: #selector(self.didTapQueueButton))
    NotificationCenter.default.addObserver(self, selector: #selector(self.castDeviceDidChange), name: NSNotification.Name.gckCastStateDidChange, object: GCKCastContext.sharedInstance())
  }

  func castDeviceDidChange(_ notification: Notification) {
    if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
      // You can present the instructions on how to use Google Cast on
      // the first time the user uses you app
      GCKCastContext.sharedInstance().presentCastInstructionsViewControllerOnce()
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    print("viewWillAppear; mediaInfo is \(self.mediaInfo), mode is \(self.playbackMode)")
    appDelegate?.isCastControlBarsEnabled = true
    if (self.playbackMode == .local) && self.localPlaybackImplicitlyPaused {
      self.localPlayerView.play()
      self.localPlaybackImplicitlyPaused = false
    }
    // Do we need to switch modes? If we're in remote playback mode but no longer
    // have a session, then switch to local playback mode. If we're in local mode
    // but now have a session, then switch to remote playback mode.
    var hasConnectedSession: Bool = (self.sessionManager.hasConnectedSession())
    if hasConnectedSession && (self.playbackMode != .remote) {
      self.populateMediaInfo(false, playPosition: 0)
      self.switchToRemotePlayback()
    }
    else if (self.sessionManager.currentSession == nil) && (self.playbackMode != .local) {
      self.switchToLocalPlayback()
    }

    self.sessionManager.add(self)
    self.gradient = CAGradientLayer()
    self.gradient.colors = [(UIColor.clear.cgColor as? Any), (UIColor(red: CGFloat((50 / 255.0)), green: CGFloat((50 / 255.0)), blue: CGFloat((50 / 255.0)), alpha: CGFloat((200 / 255.0))).cgColor as? Any)]
    self.gradient.startPoint = CGPoint(x: CGFloat(0), y: CGFloat(1))
    self.gradient.endPoint = CGPoint.zero
    var orientation: UIInterfaceOrientation = UIApplication.shared.statusBarOrientation
    if UIInterfaceOrientationIsLandscape(orientation) {
      self.setNavigationBarStyle(.lpvNavBarTransparent)
    }
    else if self.isResetEdgesOnDisappear {
      self.setNavigationBarStyle(.lpvNavBarDefault)
    }

    NotificationCenter.default.addObserver(self, selector: #selector(self.deviceOrientationDidChange), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    super.viewWillAppear(animated)
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

  override func viewWillDisappear(_ animated: Bool) {
    print("viewWillDisappear")
    self.setNavigationBarStyle(.lpvNavBarDefault)
    switch self.playbackMode {
    case PlaybackMode.local:
      if self.localPlayerView.playerState == .playing || self.localPlayerView.playerState == .starting {
        self.localPlaybackImplicitlyPaused = true
        self.localPlayerView.pause()
      }
    default:
      // Do nothing.
      break
    }

    self.sessionManager.remove(self)
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    super.viewWillDisappear(animated)
  }

  func deviceOrientationDidChange(_ notification: Notification) {
    print("Orientation changed.")
    var orientation: UIInterfaceOrientation = UIApplication.shared.statusBarOrientation
    if UIInterfaceOrientationIsLandscape(orientation) {
      self.setNavigationBarStyle(.lpvNavBarTransparent)
    }
    else if !UIInterfaceOrientationIsLandscape(orientation) || !self.localPlayerView.isPlayingLocally {
      self.setNavigationBarStyle(.lpvNavBarDefault)
    }

    self.localPlayerView.orientationChanged()
  }

  func didTapQueueButton(_ sender: Any) {
    appDelegate?.isCastControlBarsEnabled = false
    self.performSegue(withIdentifier: "MediaQueueSegue", sender: self)
  }
  // MARK: - Mode switching

  func switchToLocalPlayback() {
    print("switchToLocalPlayback")
    if self.playbackMode == .local {
      return
    }
    self.setQueueButtonVisible(false)
    var playPosition: TimeInterval = 0
    var paused: Bool = false
    var ended: Bool = false
    if self.playbackMode == .remote {
      playPosition = self.castMediaController.lastKnownStreamPosition
      paused = (self.castMediaController.lastKnownPlayerState == .paused)
      ended = (self.castMediaController.lastKnownPlayerState == .idle)
      print("last player state: \(self.castMediaController.lastKnownPlayerState), ended: \(ended)")
    }
    self.populateMediaInfo((!paused && !ended), playPosition: playPosition)
    self.castSession.remoteMediaClient?.remove(self)
    self.castSession = nil
    self.playbackMode = .local
  }

  func populateMediaInfo(_ autoPlay: Bool, playPosition: TimeInterval) {
    print("populateMediaInfo")
    self.titleLabel.text = self.mediaInfo.metadata?.string(forKey: kGCKMetadataKeyTitle)
    var subtitle: String? = self.mediaInfo.metadata?.string(forKey: kGCKMetadataKeyArtist)
    if subtitle == nil {
      subtitle = self.mediaInfo.metadata?.string(forKey: kGCKMetadataKeyStudio)
    }
    self.subtitleLabel.text = subtitle
    let description: String? = self.mediaInfo.metadata?.string(forKey: kMediaKeyDescription)
    self.descriptionTextView.text = description?.replacingOccurrences(of: "\\n", with: "\n")
    self.localPlayerView.loadMedia(self.mediaInfo, autoPlay: autoPlay, playPosition: playPosition)
  }

  func switchToRemotePlayback() {
    print("switchToRemotePlayback; mediaInfo is \(self.mediaInfo)")
    if self.playbackMode == .remote {
      return
    }
    if (self.sessionManager.currentSession is GCKCastSession) {
      self.castSession = (self.sessionManager.currentSession as? GCKCastSession)
    }
    // If we were playing locally, load the local media on the remote player
    if (self.playbackMode == .local) && (self.localPlayerView.playerState != .stopped) && (self.mediaInfo != nil) {
      print("loading media: \(self.mediaInfo)")
      let playPosition = self.localPlayerView.streamPosition
      let paused: Bool = (self.localPlayerView.playerState == .paused)
      let builder = GCKMediaQueueItemBuilder()
      builder.mediaInformation = self.mediaInfo
      builder.autoplay = !paused
      builder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
      let item: GCKMediaQueueItem? = builder.build()
      self.castSession.remoteMediaClient?.queueLoad([item!], start: 0, playPosition: playPosition!, repeatMode: .off, customData: nil)
    }
    self.localPlayerView.stop()
    self.localPlayerView.showSplashScreen()
    self.setQueueButtonVisible(true)
    self.castSession.remoteMediaClient?.add(self)
    self.playbackMode = .remote
  }

  func clearMetadata() {
    self.titleLabel.text = ""
    self.subtitleLabel.text = ""
    self.descriptionTextView.text = ""
  }

  func showAlert(withTitle title: String, message: String) {
    let alert = UIAlertView(title: title, message: message, delegate: nil, cancelButtonTitle: "OK", otherButtonTitles: "")
    alert.show()
  }
  // MARK: - Local playback UI actions

  func startAdjustingStreamPosition(_ sender: Any) {
    self.streamPositionSliderMoving = true
  }

  func finishAdjustingStreamPosition(_ sender: Any) {
    self.streamPositionSliderMoving = false
  }

  func togglePlayPause(_ sender: Any) {
    self.localPlayerView.togglePause()
  }
  // MARK: - GCKSessionManagerListener

  func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
    print("MediaViewController: sessionManager didStartSession \(session)")
    self.setQueueButtonVisible(true)
    self.switchToRemotePlayback()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
    print("MediaViewController: sessionManager didResumeSession \(session)")
    self.setQueueButtonVisible(true)
    self.switchToRemotePlayback()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    print("session ended with error: \(error)")
    let message = "The Casting session has ended.\n\((error as! NSError).description)"
    if let window = appDelegate?.window {
      Toast.displayMessage(message, for: 3, in: window)
    }
    self.setQueueButtonVisible(false)
    self.switchToLocalPlayback()
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
    self.showAlert(withTitle: "Failed to start a session", message: (error as! NSError).description)
    self.setQueueButtonVisible(false)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didFailToResumeSession session: GCKSession, withError error: Error?) {
    Toast.displayMessage("The Casting session could not be resumed.", for: 3, in: ((UIApplication.shared.delegate?.window)!)!)
    self.setQueueButtonVisible(false)
    self.switchToLocalPlayback()
  }
  // MARK: - GCKRemoteMediaClientListener

  func remoteMediaClient(_ player: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus) {
    self.mediaInfo = mediaStatus.mediaInformation
  }
  // MARK: - LocalPlayerViewDelegate
  /* Signal the requested style for the view. */

  func setNavigationBarStyle(_ style: LPVNavBarStyle) {
    if style == .lpvNavBarDefault {
      print("setNavigationBarStyle: Default")
    }
    else if style == .lpvNavBarTransparent {
      print("setNavigationBarStyle: Transparent")
    }
    else {
      print("setNavigationBarStyle: Unknown - \(style)")
    }

    if style == .lpvNavBarDefault {
      self.edgesForExtendedLayout = .all
      self.hideNavigationBar(false)
      self.navigationController?.navigationBar.isTranslucent = false
      self.navigationController?.navigationBar.setBackgroundImage(nil, for: .default)
      self.navigationController?.navigationBar.shadowImage = nil
      UIApplication.shared.setStatusBarHidden(false, with: .fade)
      self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
      self.isResetEdgesOnDisappear = false
    }
    else if style == .lpvNavBarTransparent {
      self.edgesForExtendedLayout = .top
      self.navigationController?.navigationBar.isTranslucent = true
      // Gradient background
      self.gradient.frame = (self.navigationController?.navigationBar.bounds)!
      UIGraphicsBeginImageContext(self.gradient.bounds.size)
      self.gradient.render(in: UIGraphicsGetCurrentContext()!)
      var gradientImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      self.navigationController?.navigationBar.setBackgroundImage(gradientImage, for: .default)
      self.navigationController?.navigationBar.shadowImage = UIImage()
      UIApplication.shared.setStatusBarHidden(true, with: .fade)
      // Disable the swipe gesture if we're fullscreen.
      self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
      self.isResetEdgesOnDisappear = true
    }

  }
  /* Request the navigation bar to be hidden or shown. */

  func hideNavigationBar(_ hide: Bool) {
    if hide {
      print("HIDE NavBar.")
    }
    else {
      print("SHOW NavBar.")
    }
    self.navigationController?.navigationBar.isHidden = hide
  }
  /* Play has been pressed in the LocalPlayerView. */

  func continueAfterPlayButtonClicked() -> Bool {
    let hasConnectedCastSession = GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession()
    if (self.mediaInfo != nil) && hasConnectedCastSession {
      // Display an alert box to allow the user to add to queue or play
      // immediately.
      if self.actionSheet == nil {
        self.actionSheet = ActionSheet(title: "Play Item", message: "Select an action", cancelButtonText: "Cancel")
        self.actionSheet.addAction(withTitle: "Play Now", target: self, selector: #selector(self.playSelectedItemRemotely))
        self.actionSheet.addAction(withTitle: "Add to Queue", target: self, selector: #selector(self.enqueueSelectedItemRemotely))
      }
      self.actionSheet.present(in: self, sourceView: self.localPlayerView)
      return false
    }
    return true
  }

  func playSelectedItemRemotely() {
    self.loadSelectedItem(byAppending: false)
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }

  func enqueueSelectedItemRemotely() {
    self.loadSelectedItem(byAppending: true)
    let message = "Added \"\(self.mediaInfo.metadata?.string(forKey: kGCKMetadataKeyTitle))\" to queue."
    Toast.displayMessage(message, for: 3, in: ((UIApplication.shared.delegate?.window)!)!)
    self.setQueueButtonVisible(true)
  }
  /**
   * Loads the currently selected item in the current cast media session.
   * @param appending If YES, the item is appended to the current queue if there
   * is one. If NO, or if
   * there is no queue, a new queue containing only the selected item is created.
   */

  func loadSelectedItem(byAppending appending: Bool) {
    print("enqueue item \(self.mediaInfo)")
    let session = GCKCastContext.sharedInstance().sessionManager.currentSession
    if let castSession = session as? GCKCastSession {
      if ((castSession.remoteMediaClient) != nil) {
        let builder = GCKMediaQueueItemBuilder()
        builder.mediaInformation = self.mediaInfo
        builder.autoplay = true
        builder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
        let item: GCKMediaQueueItem? = builder.build()
        if ((castSession.remoteMediaClient?.mediaStatus) != nil) && appending {
          let request: GCKRequest? = castSession.remoteMediaClient?.queueInsert(item!, beforeItemWithID: kGCKMediaQueueInvalidItemID)
          request?.delegate = self
        }
        else {
          let repeatMode = (castSession.remoteMediaClient?.mediaStatus != nil) ? castSession.remoteMediaClient?.mediaStatus?.queueRepeatMode : .off
          let request: GCKRequest? = castSession.remoteMediaClient?.queueLoad([item!], start: 0, playPosition: 0, repeatMode: repeatMode!, customData: nil)
          request?.delegate = self
        }
      }
    }
  }
  // MARK: - GCKRequestDelegate

  func requestDidComplete(_ request: GCKRequest) {
    print("request \(Int(request.requestID)) completed")
  }

  func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    print("request \(Int(request.requestID)) failed with error \(error)")
  }
}
