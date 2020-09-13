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

import GoogleCast
import UIKit

/* The player state. */
enum PlaybackMode: Int {
  case none = 0
  case local
  case remote
}

let kPrefShowStreamTimeRemaining: String = "show_stream_time_remaining"

@objc(MediaViewController)
class MediaViewController: UIViewController, GCKSessionManagerListener, GCKRemoteMediaClientListener, LocalPlayerViewDelegate, GCKRequestDelegate {
  @IBOutlet private var _titleLabel: UILabel!
  @IBOutlet private var _subtitleLabel: UILabel!
  @IBOutlet private var _descriptionTextView: UITextView!
  @IBOutlet private var _localPlayerView: LocalPlayerView!
  private var sessionManager: GCKSessionManager!
  private var castMediaController: GCKUIMediaController!
  private var volumeController: GCKUIDeviceVolumeController!
  private var streamPositionSliderMoving: Bool = false
  private var playbackMode = PlaybackMode.none
  private var queueButton: UIBarButtonItem!
  private var showStreamTimeRemaining: Bool = false
  private var localPlaybackImplicitlyPaused: Bool = false
  private var actionSheet: ActionSheet?
  private var queueAdded: Bool = false
  private var gradient: CAGradientLayer!
  private var castButton: GCKUICastButton!
  /* Whether to reset the edges on disappearing. */
  var isResetEdgesOnDisappear: Bool = false
  // The media to play.
  var mediaInfo: GCKMediaInformation? {
    didSet {
      print("setMediaInfo: \(String(describing: mediaInfo))")
    }
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    sessionManager = GCKCastContext.sharedInstance().sessionManager
    castMediaController = GCKUIMediaController()
    volumeController = GCKUIDeviceVolumeController()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    print("in MediaViewController viewDidLoad")
    _localPlayerView.delegate = self
    castButton = GCKUICastButton(frame: CGRect(x: CGFloat(0), y: CGFloat(0),
                                               width: CGFloat(24), height: CGFloat(24)))
    // Overwrite the UIAppearance theme in the AppDelegate.
    castButton.tintColor = UIColor.white
    navigationItem.rightBarButtonItem = UIBarButtonItem(customView: castButton)
    queueButton = UIBarButtonItem(image: UIImage(named: "playlist_white.png"),
                                  style: .plain, target: self, action: #selector(didTapQueueButton))
    NotificationCenter.default.addObserver(self, selector: #selector(castDeviceDidChange),
                                           name: NSNotification.Name.gckCastStateDidChange,
                                           object: GCKCastContext.sharedInstance())
  }

  @objc func castDeviceDidChange(_: Notification) {
    if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
      // You can present the instructions on how to use Google Cast on
      // the first time the user uses you app
      GCKCastContext.sharedInstance().presentCastInstructionsViewControllerOnce(with: castButton)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    print("viewWillAppear; mediaInfo is \(String(describing: mediaInfo)), mode is \(playbackMode)")
    appDelegate?.isCastControlBarsEnabled = true
    if playbackMode == .local, localPlaybackImplicitlyPaused {
      _localPlayerView.play()
      localPlaybackImplicitlyPaused = false
    }
    // If we're in remote playback but no longer have a session, then switch to local playback
    // mode. If we're in local mode but now have a session, then switch to remote playback mode.
    let hasConnectedSession: Bool = (sessionManager.hasConnectedSession())
    if hasConnectedSession, (playbackMode != .remote) {
      populateMediaInfo(false, playPosition: 0)
      switchToRemotePlayback()
    } else if sessionManager.currentSession == nil, (playbackMode != .local) {
      switchToLocalPlayback()
    }

    sessionManager.add(self)
    gradient = CAGradientLayer()
    gradient.colors = [(UIColor.clear.cgColor),
                       (UIColor(red: CGFloat((50 / 255.0)), green: CGFloat((50 / 255.0)),
                                blue: CGFloat((50 / 255.0)), alpha: CGFloat((200 / 255.0))).cgColor)]
    gradient.startPoint = CGPoint(x: CGFloat(0), y: CGFloat(1))
    gradient.endPoint = CGPoint.zero
    let orientation: UIInterfaceOrientation = UIApplication.shared.statusBarOrientation
    if orientation.isLandscape {
      setNavigationBarStyle(.lpvNavBarTransparent)
    } else if isResetEdgesOnDisappear {
      setNavigationBarStyle(.lpvNavBarDefault)
    }

    NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange),
                                           name: UIDevice.orientationDidChangeNotification, object: nil)
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    super.viewWillAppear(animated)
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

  override func viewWillDisappear(_ animated: Bool) {
    print("viewWillDisappear")
    setNavigationBarStyle(.lpvNavBarDefault)
    switch playbackMode {
    case .local:
      if _localPlayerView.playerState == .playing || _localPlayerView.playerState == .starting {
        localPlaybackImplicitlyPaused = true
        _localPlayerView.pause()
      }
    default:
      // Do nothing.
      break
    }

    sessionManager.remove(self)
    sessionManager.currentCastSession?.remoteMediaClient?.remove(self)
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    super.viewWillDisappear(animated)
  }

  @objc func deviceOrientationDidChange(_: Notification) {
    print("Orientation changed.")
    let orientation: UIInterfaceOrientation = UIApplication.shared.statusBarOrientation
    if orientation.isLandscape {
      setNavigationBarStyle(.lpvNavBarTransparent)
    } else if !orientation.isLandscape || !_localPlayerView.isPlayingLocally {
      setNavigationBarStyle(.lpvNavBarDefault)
    }

    _localPlayerView.orientationChanged()
  }

  @objc func didTapQueueButton(_: Any) {
    appDelegate?.isCastControlBarsEnabled = false
    performSegue(withIdentifier: "MediaQueueSegue", sender: self)
  }

  // MARK: - Mode switching

  func switchToLocalPlayback() {
    print("switchToLocalPlayback")
    if playbackMode == .local {
      return
    }
    setQueueButtonVisible(false)
    var playPosition: TimeInterval = 0
    var paused: Bool = false
    var ended: Bool = false
    if playbackMode == .remote {
      playPosition = castMediaController.lastKnownStreamPosition
      paused = (castMediaController.lastKnownPlayerState == .paused)
      ended = (castMediaController.lastKnownPlayerState == .idle)
      print("last player state: \(castMediaController.lastKnownPlayerState), ended: \(ended)")
    }
    populateMediaInfo((!paused && !ended), playPosition: playPosition)
    sessionManager.currentCastSession?.remoteMediaClient?.remove(self)
    playbackMode = .local
  }

  func populateMediaInfo(_ autoPlay: Bool, playPosition: TimeInterval) {
    print("populateMediaInfo")
    _titleLabel.text = mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyTitle)
    var subtitle = mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyArtist)
    if subtitle == nil {
      subtitle = mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyStudio)
    }
    _subtitleLabel.text = subtitle
    let description = mediaInfo?.metadata?.string(forKey: kMediaKeyDescription)
    _descriptionTextView.text = description?.replacingOccurrences(of: "\\n", with: "\n")
    _localPlayerView.loadMedia(mediaInfo, autoPlay: autoPlay, playPosition: playPosition)
  }

  func switchToRemotePlayback() {
    print("switchToRemotePlayback; mediaInfo is \(String(describing: mediaInfo))")
    if playbackMode == .remote {
      return
    }
    // If we were playing locally, load the local media on the remote player
    if playbackMode == .local, (_localPlayerView.playerState != .stopped), (mediaInfo != nil) {
      print("loading media: \(String(describing: mediaInfo))")
      let paused: Bool = (_localPlayerView.playerState == .paused)
      let mediaQueueItemBuilder = GCKMediaQueueItemBuilder()
      mediaQueueItemBuilder.mediaInformation = mediaInfo
      mediaQueueItemBuilder.autoplay = !paused
      mediaQueueItemBuilder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
      mediaQueueItemBuilder.startTime = _localPlayerView.streamPosition ?? 0
      let mediaQueueItem = mediaQueueItemBuilder.build()

      let queueDataBuilder = GCKMediaQueueDataBuilder(queueType: .generic)
      queueDataBuilder.items = [mediaQueueItem]
      queueDataBuilder.repeatMode = .off

      let mediaLoadRequestDataBuilder = GCKMediaLoadRequestDataBuilder()
      mediaLoadRequestDataBuilder.queueData = queueDataBuilder.build()

      let request = sessionManager.currentCastSession?.remoteMediaClient?.loadMedia(with: mediaLoadRequestDataBuilder.build())
      request?.delegate = self
    }
    _localPlayerView.stop()
    _localPlayerView.showSplashScreen()
    setQueueButtonVisible(true)
    sessionManager.currentCastSession?.remoteMediaClient?.add(self)
    playbackMode = .remote
  }

  func clearMetadata() {
    _titleLabel.text = ""
    _subtitleLabel.text = ""
    _descriptionTextView.text = ""
  }

  func showAlert(withTitle title: String, message: String) {
    let alert = UIAlertView(title: title,
                            message: message,
                            delegate: nil,
                            cancelButtonTitle: "OK",
                            otherButtonTitles: "")
    alert.show()
  }

  // MARK: - Local playback UI actions

  func startAdjustingStreamPosition(_: Any) {
    streamPositionSliderMoving = true
  }

  func finishAdjustingStreamPosition(_: Any) {
    streamPositionSliderMoving = false
  }

  func togglePlayPause(_: Any) {
    _localPlayerView.togglePause()
  }

  // MARK: - GCKSessionManagerListener

  func sessionManager(_: GCKSessionManager, didStart session: GCKSession) {
    print("MediaViewController: sessionManager didStartSession \(session)")
    setQueueButtonVisible(true)
    switchToRemotePlayback()
  }

  func sessionManager(_: GCKSessionManager, didResumeSession session: GCKSession) {
    print("MediaViewController: sessionManager didResumeSession \(session)")
    setQueueButtonVisible(true)
    switchToRemotePlayback()
  }

  func sessionManager(_: GCKSessionManager, didEnd _: GCKSession, withError error: Error?) {
    print("session ended with error: \(String(describing: error))")
    let message = "The Casting session has ended.\n\(String(describing: error))"
    if let window = appDelegate?.window {
      Toast.displayMessage(message, for: 3, in: window)
    }
    setQueueButtonVisible(false)
    switchToLocalPlayback()
  }

  func sessionManager(_: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
    if let error = error {
      showAlert(withTitle: "Failed to start a session", message: error.localizedDescription)
    }
    setQueueButtonVisible(false)
  }

  func sessionManager(_: GCKSessionManager,
                      didFailToResumeSession _: GCKSession, withError _: Error?) {
    if let window = UIApplication.shared.delegate?.window {
      Toast.displayMessage("The Casting session could not be resumed.",
                           for: 3, in: window)
    }
    setQueueButtonVisible(false)
    switchToLocalPlayback()
  }

  // MARK: - GCKRemoteMediaClientListener

  func remoteMediaClient(_: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {}

  // MARK: - LocalPlayerViewDelegate

  /* Signal the requested style for the view. */
  func setNavigationBarStyle(_ style: LPVNavBarStyle) {
    if style == .lpvNavBarDefault {
      print("setNavigationBarStyle: Default")
    } else if style == .lpvNavBarTransparent {
      print("setNavigationBarStyle: Transparent")
    } else {
      print("setNavigationBarStyle: Unknown - \(style)")
    }

    if style == .lpvNavBarDefault {
      edgesForExtendedLayout = .all
      hideNavigationBar(false)
      navigationController?.navigationBar.isTranslucent = false
      navigationController?.navigationBar.setBackgroundImage(nil, for: .default)
      navigationController?.navigationBar.shadowImage = nil
      UIApplication.shared.setStatusBarHidden(false, with: .fade)
      navigationController?.interactivePopGestureRecognizer?.isEnabled = true
      isResetEdgesOnDisappear = false
    } else if style == .lpvNavBarTransparent {
      edgesForExtendedLayout = .top
      navigationController?.navigationBar.isTranslucent = true
      // Gradient background
      if let bounds = navigationController?.navigationBar.bounds {
        gradient.frame = bounds
      }
      UIGraphicsBeginImageContext(gradient.bounds.size)
      if let context = UIGraphicsGetCurrentContext() {
        gradient.render(in: context)
      }
      let gradientImage: UIImage? = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      navigationController?.navigationBar.setBackgroundImage(gradientImage, for: .default)
      navigationController?.navigationBar.shadowImage = UIImage()
      UIApplication.shared.setStatusBarHidden(true, with: .fade)
      // Disable the swipe gesture if we're fullscreen.
      navigationController?.interactivePopGestureRecognizer?.isEnabled = false
      isResetEdgesOnDisappear = true
    }
  }

  /* Request the navigation bar to be hidden or shown. */
  func hideNavigationBar(_ hide: Bool) {
    if hide {
      print("HIDE NavBar.")
    } else {
      print("SHOW NavBar.")
    }
    navigationController?.navigationBar.isHidden = hide
  }

  /* Play has been pressed in the LocalPlayerView. */
  func continueAfterPlayButtonClicked() -> Bool {
    let hasConnectedCastSession = sessionManager.hasConnectedCastSession
    if mediaInfo != nil, hasConnectedCastSession() {
      // Display an alert box to allow the user to add to queue or play
      // immediately.
      if actionSheet == nil {
        actionSheet = ActionSheet(title: "Play Item", message: "Select an action", cancelButtonText: "Cancel")
        actionSheet?.addAction(withTitle: "Play Now", target: self,
                               selector: #selector(playSelectedItemRemotely))
        actionSheet?.addAction(withTitle: "Add to Queue", target: self,
                               selector: #selector(enqueueSelectedItemRemotely))
      }
      actionSheet?.present(in: self, sourceView: _localPlayerView)
      return false
    }
    return true
  }

  @objc func playSelectedItemRemotely() {
    loadSelectedItem(byAppending: false)
    appDelegate?.isCastControlBarsEnabled = false
    GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
  }

  @objc func enqueueSelectedItemRemotely() {
    loadSelectedItem(byAppending: true)
    let message = "Added \"\(mediaInfo?.metadata?.string(forKey: kGCKMetadataKeyTitle) ?? "")\" to queue."
    if let window = UIApplication.shared.delegate?.window {
      Toast.displayMessage(message, for: 3, in: window)
    }
    setQueueButtonVisible(true)
  }

  /**
   * Loads the currently selected item in the current cast media session.
   * @param appending If YES, the item is appended to the current queue if there
   * is one. If NO, or if
   * there is no queue, a new queue containing only the selected item is created.
   */
  func loadSelectedItem(byAppending appending: Bool) {
    print("enqueue item \(String(describing: mediaInfo))")
    if let remoteMediaClient = sessionManager.currentCastSession?.remoteMediaClient {
      let mediaQueueItemBuilder = GCKMediaQueueItemBuilder()
      mediaQueueItemBuilder.mediaInformation = mediaInfo
      mediaQueueItemBuilder.autoplay = true
      mediaQueueItemBuilder.preloadTime = TimeInterval(UserDefaults.standard.integer(forKey: kPrefPreloadTime))
      let mediaQueueItem = mediaQueueItemBuilder.build()
      if appending {
        let request = remoteMediaClient.queueInsert(mediaQueueItem, beforeItemWithID: kGCKMediaQueueInvalidItemID)
        request.delegate = self
      } else {
        let queueDataBuilder = GCKMediaQueueDataBuilder(queueType: .generic)
        queueDataBuilder.items = [mediaQueueItem]
        queueDataBuilder.repeatMode = remoteMediaClient.mediaStatus?.queueRepeatMode ?? .off

        let mediaLoadRequestDataBuilder = GCKMediaLoadRequestDataBuilder()
        mediaLoadRequestDataBuilder.queueData = queueDataBuilder.build()

        let request = remoteMediaClient.loadMedia(with: mediaLoadRequestDataBuilder.build())
        request.delegate = self
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
