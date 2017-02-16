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

import AVFoundation
import GoogleCast
/* Time to wait before hiding the toolbar. UX is that this number is effectively
 * doubled. */
var kToolbarDelay: Int = 3

/* The height of the toolbar view. */
var kToolbarHeight: Int = 44

/* Protocol for callbacks from the LocalPlayerView. */
protocol LocalPlayerViewDelegate: NSObjectProtocol {
  /* Signal the requested style for the view. */
  func setNavigationBarStyle(_ style: LPVNavBarStyle)
  /* Request the navigation bar to be hidden or shown. */

  func hideNavigationBar(_ hide: Bool)
  /* Play has beeen pressed in the LocalPlayerView.
   * Return NO to halt default actions, YES to continue as normal.
   */
  func continueAfterPlayButtonClicked() -> Bool
}

/* Navigation Bar styles/ */
enum LPVNavBarStyle : Int {
  case lpvNavBarTransparent
  case lpvNavBarDefault
}

/* The player state. */
enum LocalPlayerState : Int {
  case stopped
  case starting
  case playing
  case paused
}

/* UIView for displaying a local player or splash screen. */
class LocalPlayerView: UIView {
  var mediaPlayer: AVPlayer!
  var mediaPlayerLayer: AVPlayerLayer!
  var mediaTimeObserver: Any!
  var observingMediaPlayer: Bool = false
  // If there is a pending request to seek to a new position.
  var pendingPlayPosition = TimeInterval()
  // If there is a pending request to start playback.
  var pendingPlay: Bool = false
  // If a seek is currently in progress.
  var seeking: Bool = false


  /* The aspect ratio constraint for the view. */
  @IBOutlet weak var viewAspectRatio: NSLayoutConstraint!
  /* The splash image to display before playback or while casting. */
  var splashImage: UIImageView!
  /* The UIView used for receiving control input. */
  var controlView: UIView!
  /* The gesture recognizer used to register taps to bring up the controls. */
  var singleFingerTap: UIGestureRecognizer!
  /* Whether there has been a recent touch, for fading controls when playing. */
  var isRecentInteraction: Bool = false
  /* Views dictionary used to the layout management. */
  var viewsDictionary: [AnyHashable: Any]?
  /* Views dictionary used to the layout management. */
  var constraints: [Any]?
  /* Play/Pause button. */
  var playButton: UIButton!
  /* Splash play button. */
  var splashPlayButton: UIButton!
  /* Playback position slider. */
  var slider: UISlider!
  /* Label displaying length of video. */
  var totalTime: UILabel!
  /* View for containing play controls. */
  var toolbarView: UIView!
  /* Play image. */
  var playImage: UIImage!
  /* Pause image. */
  var pauseImage: UIImage!
  /* Loading indicator */
  var activityIndicator: UIActivityIndicatorView!
  /* Delegate to use for callbacks for play/pause presses while in Cast mode. */
  weak var delegate: LocalPlayerViewDelegate?
  /* Local player elapsed time. */
  private(set) var streamPosition: TimeInterval?
  /* Local player media duration. */
  private(set) var streamDuration: TimeInterval?
  /* YES if the video is playing or paused in the local player. */
  var isPlayingLocally: Bool {
    return playerState == .playing || playerState == .paused
  }
  /* YES if the video is fullscreen. */
  var isFullscreen: Bool {
    let full: Bool = (playerState != .stopped) && UIInterfaceOrientationIsLandscape(UIApplication.shared.statusBarOrientation)
    print("fullscreen=\(full)")
    return full
  }
  /* The media we are playing. */
  private(set) var media: GCKMediaInformation!
  /* The current player state. */
  private(set) var playerState = LocalPlayerState(rawValue: 0)
  /* Signal an orientation change has occurred. */

  func orientationChanged() {
    if isFullscreen {
      setFullscreen()
    }
    didTouchControl(nil)
  }

  func loadMedia(_ media: GCKMediaInformation, autoPlay: Bool, playPosition: TimeInterval) {
    print("loadMedia \(autoPlay)")
    if media != nil && (media.contentID == media.contentID) {
      // Don't reinit if we already have the media.
      return
    }
    media = media
    if media == nil {
      purgeMediaPlayer()
      return
    }
    translatesAutoresizingMaskIntoConstraints = false
    playerState = .stopped
    splashImage = UIImageView(frame: fullFrame())
    splashImage.contentMode = .scaleAspectFill
    splashImage.clipsToBounds = true
    addSubview(splashImage)
    // Single-tap control view to bring controls back to the front.
    controlView = UIView()
    singleFingerTap = UITapGestureRecognizer(target: self, action: #selector(didTouchControl))
    controlView.addGestureRecognizer(singleFingerTap)
    addSubview(controlView)
    // Play overlay that users can tap to get started.
    var giantPlayButton = UIImage(named: "play_circle")
    splashPlayButton = UIButton(type: .system)
    splashPlayButton.frame = fullFrame()
    splashPlayButton.contentMode = .center
    splashPlayButton.setImage(giantPlayButton, for: .normal)
    splashPlayButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    splashPlayButton.addTarget(self, action: #selector(playButtonClicked), for: .touchUpInside)
    splashPlayButton.tintColor = UIColor.white
    addSubview(splashPlayButton)
    pendingPlayPosition = playPosition
    pendingPlay = autoPlay
    initialiseToolbarControls()
    loadMediaImage()
    configureControls()
  }

  func pause() {
    if playerState == .playing {
      playButtonClicked(self)
    }
  }

  func play() {
    if seeking {
      pendingPlay = true
    }
    else if playerState == .paused {
      mediaPlayer.play()
      playerState = .playing
    }
    else if playerState == .starting {
      playerState = .playing
    }

  }

  func stop() {
    purgeMediaPlayer()
    playerState = .stopped
  }

  func togglePause() {
    switch playerState {
    case .paused:
      play()
    case .playing:
      pause()
    default:
      // Do nothing.
      break
    }

  }

  func seek(toTime time: TimeInterval) {
    switch playerState {
    case .playing:
      pendingPlay = true
      performSeek(toTime: time)
    case .paused:
      pendingPlay = false
      performSeek(toTime: time)
    case .starting:
      pendingPlayPosition = time
    default:
      break
    }

  }
  /* Reset the state of the player to show the splash screen. */

  func showSplashScreen() {
    // Treat movie as finished to reset.
    handleMediaPlaybackEnded()
  }


  deinit {
    purgeMediaPlayer()
    NotificationCenter.default.removeObserver(self)
  }
  // MARK: - Layout Managment

  override func layoutSubviews() {
    var frame: CGRect = isFullscreen ? UIScreen.main.bounds : fullFrame()
    if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1) && isFullscreen {
      // Below iOS 8 the bounds don't change with orientation changes.
      frame.size = CGSize(width: CGFloat(frame.size.height), height: CGFloat(frame.size.width))
    }
    splashImage.frame = frame
    mediaPlayerLayer.frame = frame
    controlView.frame = frame
    layoutToolbar(frame)
    activityIndicator.center = controlView.center
  }
  /* Update the frame for the toolbar. */

  func layoutToolbar(_ frame: CGRect) {
    toolbarView.frame = CGRect(x: CGFloat(0), y: CGFloat(frame.size.height - kToolbarHeight), width: CGFloat(frame.size.width), height: CGFloat(kToolbarHeight))
  }
  /* Return the full frame with no offsets. */

  func fullFrame() -> CGRect {
    return CGRect(x: CGFloat(0), y: CGFloat(0), width: CGFloat(frame.size.width), height: CGFloat(frame.size.height))
  }

  override func updateConstraints() {
    super.updateConstraints()
    // Active is iOS 8 only, so only do this if available.
    if viewAspectRatio.responds(to: #selector(setActive)) {
      viewAspectRatio.isActive = !isFullscreen
    }
  }
  // MARK: - Public interface
  /* YES if we the local media is playing or paused, NO if casting or on the
   * splash screen. */
  // MARK: -
  /* Returns YES if we should be in fullscreen. */
  /* If the orientation changes, display the controls. */

  func setFullscreen() {
    print("setFullscreen")
    delegate.navigationBarStyle = .lpvNavBarTransparent
    var screenBounds: CGRect = UIScreen.main.bounds
    if !screenBounds.equalTo(frame) {
      print("hideNavigationBar: set fullscreen")
      frame = screenBounds
    }
  }
  // MARK: - Media player management
  /* Asynchronously load the splash screen image. */

  func loadMediaImage() {
    var images: [Any] = media.metadata().images
    if images && images.count > 0 {
      var image: GCKImage? = images[0]
      GCKCastContext.sharedInstance().imageCache?.fetchImage(for: (image?.url)!, completion: {(_ image: UIImage) -> Void in
        splashImage.image = image
      })
    }
  }

  func loadMediaPlayer() {
    if let mediaPlayer = mediaPlayer {
      var mediaURL = URL(string: media.contentID)
      mediaPlayer = AVPlayer.withURL(mediaURL)
      mediaPlayerLayer = AVPlayerLayer(mediaPlayer)
      mediaPlayerLayer.frame = fullFrame()
      mediaPlayerLayer.backgroundColor = UIColor.black.cgColor
      layer.insertSublayer(mediaPlayerLayer, above: splashImage.layer)
      addMediaPlayerObservers()
    }
  }

  func purgeMediaPlayer() {
    removeMediaPlayerObservers()
    mediaPlayerLayer.removeFromSuperlayer()
    mediaPlayerLayer = nil
    mediaPlayer = nil
    pendingPlayPosition = kGCKInvalidTimeInterval
    pendingPlay = true
    seeking = false
  }

  func handleMediaPlayerReady() {
    print("handleMediaPlayerReady \(pendingPlay)")
    if CMTIME_IS_INDEFINITE((mediaPlayer.currentItem?.duration)!) {
      // Loading has failed, try it again.
      purgeMediaPlayer()
      loadMediaPlayer()
      return
    }
    if !streamDuration {
      streamDuration = slider.maximumValue = CMTimeGetSeconds(mediaPlayer.currentItem.duration)
      slider.minimumValue = 0
      slider.isEnabled = true
      totalTime.text = GCKUIUtils.timeInterval(asString: streamDuration)
    }
    if !isnan(pendingPlayPosition) && pendingPlayPosition > 0 {
      print("seeking to pending position \(pendingPlayPosition)")
      performSeek(toTime: pendingPlayPosition)
      pendingPlayPosition = kGCKInvalidTimeInterval
      return
    }
    else {
      activityIndicator.stopAnimating()
    }
    if pendingPlay {
      pendingPlay = false
      mediaPlayer.play()
      playerState = .playing
    }
    else {
      playerState = .paused
    }
  }

  func performSeek(toTime time: TimeInterval) {
    print("performSeekToTime")
    activityIndicator.startAnimating()
    seeking = true
    weak var weakSelf: LocalPlayerView? = self
    mediaPlayer.seek(toTime: CMTimeMakeWithSeconds(time, 1), completionHandler: {(_ finished: Bool) -> Void in
      var strongSelf: LocalPlayerView? = weakSelf
      if strongSelf != nil {
        if strongSelf?.playerState == .starting {
          pendingPlay = true
        }
        strongSelf?.handleSeekFinished()
      }
    })
  }

  func handleSeekFinished() {
    print("handleSeekFinished \(pendingPlay)")
    activityIndicator.stopAnimating()
    if pendingPlay {
      pendingPlay = false
      mediaPlayer.play()
      playerState = .playing
    }
    else {
      playerState = .paused
    }
    seeking = false
  }
  /* Callback registered for when the AVPlayer completes playing of the media. */

  func handleMediaPlaybackEnded() {
    playerState = .stopped
    streamDuration = 0
    streamPosition = 0
    slider.value = 0
    purgeMediaPlayer()
    delegate.navigationBarStyle = .lpvNavBarDefault
    mediaPlayer.seek(toTime: CMTimeMake(0, 1))
    configureControls()
  }

  func notifyStreamPositionChanged(_ time: CMTime) {
    if (mediaPlayer.currentItem?.status != .readyToPlay) || seeking {
      return
    }
    streamPosition = (CMTimeGetSeconds(time) as? TimeInterval)
    slider.value = streamPosition
    var remainingTime: TimeInterval = (streamDuration > streamPosition) ? (streamDuration - streamPosition) : 0
    if remainingTime > 0 {
      remainingTime = -remainingTime
    }
    totalTime.text = GCKUIUtils.timeInterval(asString: remainingTime)
  }
  // MARK: - Controls
  /* Prefer the toolbar for touches when in control view. */

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if isFullscreen {
      print("TOUCH TEST")
      if controlView.isHidden {
        didTouchControl(nil)
        return nil
      }
      else if point.y > frame.size.height - kToolbarHeight {
        return controlView.hitTest(point, with: event)!
      }
    }
    return super.hitTest(point, with: event)!
  }
  /* Take the appropriate action when the play/pause button is clicked - depending
   * on the state this may start the movie, pause the movie, or start or pause
   * casting. */

  @IBAction func playButtonClicked(_ sender: Any) {
    print("playButtonClicked \(pendingPlay)")
    var delegate: LocalPlayerViewDelegate = self.delegate!
    if playerState == .stopped && delegate && delegate.responds(to: #selector(continueAfterPlayButtonClicked)) {
      if !delegate.continueAfterPlayButtonClicked() {
        return
      }
    }
    isRecentInteraction = true
    if playerState == .stopped {
      loadMediaPlayer()
      slider.isEnabled = false
      activityIndicator.startAnimating()
      if (mediaPlayer.currentItem != nil) && !CMTIME_IS_INDEFINITE((mediaPlayer.currentItem?.duration)!) {
        handleMediaPlayerReady()
      }
      else {
        playerState = .starting
      }
    }
    else if playerState == .playing {
      mediaPlayer.pause()
      playerState = .paused
    }
    else if playerState == .paused {
      mediaPlayer.play()
      playerState = .playing
    }

    configureControls()
  }
  /* If we touch the slider, stop the movie while we scrub. */

  @IBAction func onSliderTouchStarted(_ sender: Any) {
    mediaPlayer.rate = 0.0
    isRecentInteraction = true
  }
  /* Once we let go of the slider, restart playback. */

  @IBAction func onSliderTouchEnded(_ sender: Any) {
    mediaPlayer.rate = 1.0
  }
  /* On slider value change the movie play time. */

  @IBAction func onSliderValueChanged(_ sender: Any) {
    if streamDuration {
      var newTime: CMTime = CMTimeMakeWithSeconds(Float64(slider.value), 1)
      activityIndicator.startAnimating()
      mediaPlayer.seek(toTime: newTime)
    }
    else {
      slider.value = 0
    }
  }
  /* Config the UIView controls container based on the state of the view. */

  func configureControls() {
    print("configureControls \(Int(playerState))")
    if playerState == .stopped {
      playButton.setImage(playImage, for: .normal)
      splashPlayButton.isHidden = false
      splashImage.layer.isHidden = false
      mediaPlayerLayer.isHidden = true
      controlView.isHidden = true
    }
    else if playerState == .playing || playerState == .paused || playerState == .starting {
      // Play or Pause button based on state.
      var image: UIImage? = playerState == .paused ? playImage : pauseImage
      playButton.setImage(image, for: .normal)
      playButton.isHidden = false
      splashPlayButton.isHidden = true
      mediaPlayerLayer.isHidden = false
      splashImage.layer.isHidden = true
      controlView.isHidden = false
    }

    didTouchControl(nil)
    setNeedsLayout()
  }

  func showControls() {
    toolbarView.isHidden = false
  }

  func hideControls() {
    toolbarView.isHidden = true
    if isFullscreen {
      print("hideNavigationBar: hide controls")
      delegate?.hideNavigationBar(true)
    }
  }
  /* Initial setup of the controls in the toolbar. */

  func initialiseToolbarControls() {
    var frame: CGRect = fullFrame()
    // Play/Pause images.
    playImage = UIImage(named: "play")
    pauseImage = UIImage(named: "pause")
    // Toolbar.
    toolbarView = UIView()
    layoutToolbar(frame)
    // Background gradient
    var gradient = CAGradientLayer()
    gradient.frame = toolbarView.bounds
    gradient.colors = [(UIColor.clear.cgColor as? Any), (UIColor(red: CGFloat((50 / 255.0)), green: CGFloat((50 / 255.0)), blue: CGFloat((50 / 255.0)), alpha: CGFloat((200 / 255.0))).cgColor as? Any)]
    gradient.startPoint = CGPoint.zero
    gradient.endPoint = CGPoint(x: CGFloat(0), y: CGFloat(1))
    // Play/Pause button.
    playButton = UIButton(type: UIButtonTypeSystem)
    playButton.frame = CGRect(x: CGFloat(0), y: CGFloat(0), width: CGFloat(40), height: CGFloat(40))
    playButton.setImage(playImage, for: .normal)
    playButton.addTarget(self, action: #selector(playButtonClicked), for: .touchUpInside)
    playButton.tintColor = UIColor.white
    playButton.translatesAutoresizingMaskIntoConstraints = false
    // Total time.
    totalTime = UILabel()
    totalTime.clearsContextBeforeDrawing = true
    totalTime.text = "00:00"
    totalTime.font = UIFont(name: "Helvetica", size: CGFloat(14.0))
    totalTime.textColor = UIColor.white
    totalTime.tintColor = UIColor.white
    totalTime.translatesAutoresizingMaskIntoConstraints = false
    // Slider.
    slider = UISlider()
    var thumb = UIImage(named: "thumb")
    // TODO new image
    slider.setThumbImage(thumb, for: .normal)
    slider.setThumbImage(thumb, for: .highlighted)
    slider.addTarget(self, action: #selector(onSliderValueChanged), for: .valueChanged)
    slider.addTarget(self, action: #selector(onSliderTouchStarted), for: .touchDown)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchUpInside)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchCancel)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchUpOutside)
    slider.autoresizingMask = .flexibleWidth
    slider.minimumValue = 0
    slider.minimumTrackTintColor = UIColor(red: CGFloat(15.0 / 255), green: CGFloat(153.0 / 255), blue: CGFloat(242.0 / 255), alpha: CGFloat(1.0))
    slider.translatesAutoresizingMaskIntoConstraints = false
    toolbarView.addSubview(playButton)
    toolbarView.addSubview(totalTime)
    toolbarView.addSubview(slider)
    toolbarView.layer.insertSublayer(gradient, at: 0)
    controlView.insertSubview(toolbarView, at: 0)
    activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    activityIndicator.hidesWhenStopped = true
    controlView.insertSubview(activityIndicator, aboveSubview: toolbarView)
    // Layout.
    var hlayout: String = "|-[playButton(==40)]-5-[slider(>=120)]" +
    "-[totalTime(>=40)]-|"
    var vlayout: String = "V:|[playButton(==40)]"
    viewsDictionary = ["slider": slider, "totalTime": totalTime, "playButton": playButton]
    toolbarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: hlayout, options: .alignAllCenterY, metrics: nil, views: viewsDictionary))
    toolbarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: vlayout, options: [], metrics: nil, views: viewsDictionary))
  }
  /* Hide the tool bar, and the navigation controller if in the appropriate state.
   * If there has been a recent interaction, retry in kToolbarDelay seconds. */

  func hideToolBar() {
    print("hideToolBar \(playerState)")
    if !(playerState == .playing || playerState == .starting) {
      return
    }
    if isRecentInteraction {
      isRecentInteraction = false
      perform(#selector(hideToolBar), with: self, afterDelay: TimeInterval(kToolbarDelay))
    }
    else {
      UIView.animate(withDuration: 0.5, animations: {() -> Void in
        self.toolbarView.alpha = 0
      }, completion: {(_ finished: Bool) -> Void in
        self.hideControls()
        self.toolbarView.alpha = 1
      })
    }
  }
  /* Called when used touches the controlView. Display the controls, and if the
   * user is playing
   * set a timeout to hide them again. */

  func didTouchControl(_ sender: Any?) {
    print("didTouchControl \(playerState)")
    showControls()
    print("hideNavigationBar: did touch control")
    delegate?.hideNavigationBar(false)
    isRecentInteraction = true
    if playerState == .playing || playerState == .starting {
     perform(#selector(hideToolBar), with: self, afterDelay: TimeInterval(kToolbarDelay))
    }
  }
  // MARK: - KVO
  // Register observers for the media time callbacks and for the end of playback
  // notification.

  func addMediaPlayerObservers() {
    print("addMediaPlayerObservers")
    // We take a weak reference to self to avoid retain cycles in the block.
    weak var weakSelf: LocalPlayerView? = self
    mediaTimeObserver = mediaPlayer.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 1), queue: nil, using: {(_ time: CMTime) -> Void in
      var strongSelf: LocalPlayerView? = weakSelf
      if strongSelf != { _ in } {
        strongSelf?.notifyStreamPositionChanged(time)
      }
    })
    NotificationCenter.default.addObserver(self, selector: #selector(handleMediaPlaybackEnded), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: mediaPlayer.currentItem)
    mediaPlayer.currentItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
    mediaPlayer.currentItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
    mediaPlayer.currentItem?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
    observingMediaPlayer = true
  }

  func removeMediaPlayerObservers() {
    print("removeMediaPlayerObservers")
    if observingMediaPlayer {
      if (mediaTimeObserver != nil) {
        mediaPlayer.removeTimeObserver(mediaTimeObserver)
        mediaTimeObserver = nil
      }
      if (mediaPlayer.currentItem != nil) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: mediaPlayer.currentItem)
      }
      mediaPlayer.currentItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
      mediaPlayer.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
      mediaPlayer.currentItem?.removeObserver(self, forKeyPath: "status")
      observingMediaPlayer = false
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    print("observeValueForKeyPath \(keyPath)")
    guard let currentItem = mediaPlayer.currentItem, let object = object as? AVPlayerItem, object == currentItem else {
      return
    }
    if (keyPath == "playbackLikelyToKeepUp") {
      activityIndicator.stopAnimating()
    }
    else if (keyPath == "playbackBufferEmpty") {
      activityIndicator.startAnimating()
    }
    else if (keyPath == "status") {
      if mediaPlayer.status == .readyToPlay {
        handleMediaPlayerReady()
      }
    }

  }
}
