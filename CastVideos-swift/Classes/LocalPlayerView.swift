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

import AVFoundation
import GoogleCast
import UIKit

/* Time to wait before hiding the toolbar. UX is that this number is effectively
 * doubled. */
var kToolbarDelay: Int = 3
var kToolbarHeight: CGFloat = 44

protocol LocalPlayerViewDelegate: NSObjectProtocol {
  func setNavigationBarStyle(_ style: LPVNavBarStyle)
  func hideNavigationBar(_ hide: Bool)
  func continueAfterPlayButtonClicked() -> Bool
}

enum LPVNavBarStyle: Int {
  case lpvNavBarTransparent
  case lpvNavBarDefault
}

enum LocalPlayerState: Int {
  case stopped
  case starting
  case playing
  case paused
}

/* UIView for displaying a local player or splash screen. */
@objc(LocalPlayerView)
class LocalPlayerView: UIView {
  private var mediaPlayer: AVPlayer?
  private var mediaPlayerLayer: AVPlayerLayer?
  private var mediaTimeObserver: Any?
  private var observingMediaPlayer: Bool = false
  // If there is a pending request to seek to a new position.
  private var pendingPlayPosition = TimeInterval()
  // If there is a pending request to start playback.
  var pendingPlay: Bool = false
  var seeking: Bool = false

  @IBOutlet var viewAspectRatio: NSLayoutConstraint?
  var splashImage: UIImageView!
  /* The UIView used for receiving control input. */
  var controlView: UIView!
  var singleFingerTap: UIGestureRecognizer!
  var isRecentInteraction: Bool = false
  var playButton: UIButton!
  var splashPlayButton: UIButton!
  var slider: UISlider!
  var totalTime: UILabel!
  var toolbarView: UIView!
  var gradientLayer: CAGradientLayer?
  var playImage: UIImage!
  var pauseImage: UIImage!
  var activityIndicator: UIActivityIndicatorView!
  weak var delegate: LocalPlayerViewDelegate?
  private(set) var streamPosition: TimeInterval?
  private(set) var streamDuration: TimeInterval?
  var isPlayingLocally: Bool {
    return playerState == .playing || playerState == .paused
  }

  var isFullscreen: Bool {
    let full: Bool = (playerState != .stopped) &&
      UIApplication.shared.statusBarOrientation.isLandscape
    print("fullscreen=\(full)")
    return full
  }

  /* The media we are playing. */
  private(set) var media: GCKMediaInformation?
  private(set) var playerState = LocalPlayerState.stopped

  func orientationChanged() {
    if isFullscreen {
      setFullscreen()
    }
    didTouchControl(nil)
  }

  func loadMedia(_ media: GCKMediaInformation?, autoPlay: Bool, playPosition: TimeInterval) {
    print("loadMedia \(autoPlay)")
    if self.media?.contentID == media?.contentID {
      // Don't reinit if we already have the media.
      return
    }
    self.media = media
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
    let giantPlayButton = UIImage(named: "play_circle")
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
    } else if playerState == .paused {
      mediaPlayer?.play()
      playerState = .playing
    } else if playerState == .starting {
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
    if NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1, isFullscreen {
      // Below iOS 8 the bounds don't change with orientation changes.
      frame.size = CGSize(width: frame.size.height, height: frame.size.width)
    }
    splashImage.frame = frame
    mediaPlayerLayer?.frame = frame
    controlView.frame = frame
    layoutToolbar(frame)
    activityIndicator.center = controlView.center
  }

  /* Update the frame for the toolbar. */
  func layoutToolbar(_ frame: CGRect) {
    toolbarView.frame = CGRect(x: 0, y: frame.size.height - kToolbarHeight,
                               width: frame.size.width, height: kToolbarHeight)
    gradientLayer?.frame = toolbarView.bounds
  }

  /* Return the full frame with no offsets. */
  func fullFrame() -> CGRect {
    return bounds
  }

  override func updateConstraints() {
    super.updateConstraints()
    viewAspectRatio?.isActive = !isFullscreen
  }

  // MARK: - Public interface

  /* YES if we the local media is playing or paused, NO if casting or on the
   * splash screen. */

  // MARK: -

  /* Returns YES if we should be in fullscreen. */
  /* If the orientation changes, display the controls. */
  func setFullscreen() {
    print("setFullscreen")
    delegate?.setNavigationBarStyle(.lpvNavBarTransparent)
    let screenBounds: CGRect = UIScreen.main.bounds
    if !screenBounds.equalTo(frame) {
      print("hideNavigationBar: set fullscreen")
      frame = screenBounds
    }
  }

  // MARK: - Media player management

  /* Asynchronously load the splash screen image. */
  func loadMediaImage() {
    if let images = media?.metadata?.images(), !images.isEmpty {
      if let imageToFetch = images[0] as? GCKImage {
        GCKCastContext.sharedInstance().imageCache?.fetchImage(for: imageToFetch.url) { image in
          self.splashImage.image = image
        }
      }
    }
  }

  func loadMediaPlayer() {
    if mediaPlayer == nil {
      if let contentID = media?.contentID {
        if let mediaURL = URL(string: contentID) {
          mediaPlayer = AVPlayer(url: mediaURL)
          mediaPlayerLayer = AVPlayerLayer(player: mediaPlayer)
          if let mediaPlayerLayer = mediaPlayerLayer {
            mediaPlayerLayer.frame = fullFrame()
            mediaPlayerLayer.backgroundColor = UIColor.black.cgColor
            layer.insertSublayer(mediaPlayerLayer, above: splashImage.layer)
          }
          addMediaPlayerObservers()
        }
      }
    }
  }

  func purgeMediaPlayer() {
    removeMediaPlayerObservers()
    mediaPlayerLayer?.removeFromSuperlayer()
    mediaPlayerLayer = nil
    mediaPlayer = nil
    pendingPlayPosition = kGCKInvalidTimeInterval
    pendingPlay = true
    seeking = false
  }

  func handleMediaPlayerReady() {
    print("handleMediaPlayerReady \(pendingPlay)")
    if let duration = mediaPlayer?.currentItem?.duration, CMTIME_IS_INDEFINITE(duration) {
      // Loading has failed, try it again.
      purgeMediaPlayer()
      loadMediaPlayer()
      return
    }
    if streamDuration == nil {
      if let duration = mediaPlayer?.currentItem?.duration {
        streamDuration = CMTimeGetSeconds(duration)
        if let streamDuration = streamDuration {
          slider.maximumValue = Float(streamDuration)
          slider.minimumValue = 0
          slider.isEnabled = true
          totalTime.text = GCKUIUtils.timeInterval(asString: streamDuration)
        }
      }
    }
    if !pendingPlayPosition.isNaN, pendingPlayPosition > 0 {
      print("seeking to pending position \(pendingPlayPosition)")
      performSeek(toTime: pendingPlayPosition)
      pendingPlayPosition = kGCKInvalidTimeInterval
      return
    } else {
      activityIndicator.stopAnimating()
    }
    if pendingPlay {
      pendingPlay = false
      mediaPlayer?.play()
      playerState = .playing
    } else {
      playerState = .paused
    }
  }

  func performSeek(toTime time: TimeInterval) {
    print("performSeekToTime")
    activityIndicator.startAnimating()
    seeking = true
    mediaPlayer?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 1)) { [weak self] _ in
      if self?.playerState == .starting {
        self?.pendingPlay = true
      }
      self?.handleSeekFinished()
    }
  }

  func handleSeekFinished() {
    print("handleSeekFinished \(pendingPlay)")
    activityIndicator.stopAnimating()
    if pendingPlay {
      pendingPlay = false
      mediaPlayer?.play()
      playerState = .playing
    } else {
      playerState = .paused
    }
    seeking = false
  }

  /* Callback registered for when the AVPlayer completes playing of the media. */
  @objc func handleMediaPlaybackEnded() {
    playerState = .stopped
    streamDuration = 0
    streamPosition = 0
    slider.value = 0
    purgeMediaPlayer()
    delegate?.setNavigationBarStyle(.lpvNavBarDefault)
    mediaPlayer?.seek(to: CMTimeMake(value: 0, timescale: 1))
    configureControls()
  }

  func notifyStreamPositionChanged(_ time: CMTime) {
    if (mediaPlayer?.currentItem?.status != .readyToPlay) || seeking {
      return
    }
    streamPosition = CMTimeGetSeconds(time)
    guard let streamDuration = streamDuration, let streamPosition = streamPosition else { return }
    slider.value = Float(streamPosition)
    var remainingTime: TimeInterval = (Float(streamDuration) > Float(streamPosition)) ?
      (streamDuration - streamPosition) : 0
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
      } else if point.y > frame.size.height - kToolbarHeight {
        return controlView.hitTest(point, with: event)
      }
    }
    return super.hitTest(point, with: event)
  }

  /* Take the appropriate action when the play/pause button is clicked - depending
   * on the state this may start the movie, pause the movie, or start or pause
   * casting. */
  @IBAction func playButtonClicked(_: Any) {
    print("playButtonClicked \(pendingPlay)")
    if playerState == .stopped {
      if let delegate = self.delegate {
        if !delegate.continueAfterPlayButtonClicked() {
          return
        }
      }
    }
    isRecentInteraction = true
    if playerState == .stopped {
      loadMediaPlayer()
      slider.isEnabled = false
      activityIndicator.startAnimating()
      if let currentItem = mediaPlayer?.currentItem, !CMTIME_IS_INDEFINITE(currentItem.duration) {
        handleMediaPlayerReady()
      } else {
        playerState = .starting
      }
    } else if playerState == .playing {
      mediaPlayer?.pause()
      playerState = .paused
    } else if playerState == .paused {
      mediaPlayer?.play()
      playerState = .playing
    }
    configureControls()
  }

  /* If we touch the slider, stop the movie while we scrub. */
  @IBAction func onSliderTouchStarted(_: Any) {
    mediaPlayer?.rate = 0.0
    isRecentInteraction = true
  }

  /* Once we let go of the slider, restart playback. */
  @IBAction func onSliderTouchEnded(_: Any) {
    mediaPlayer?.rate = 1.0
  }

  /* On slider value change the movie play time. */
  @IBAction func onSliderValueChanged(_: Any) {
    if streamDuration != nil {
      let newTime: CMTime = CMTimeMakeWithSeconds(Float64(slider.value), preferredTimescale: 1)
      activityIndicator.startAnimating()
      mediaPlayer?.seek(to: newTime)
    } else {
      slider.value = 0
    }
  }

  /* Config the UIView controls container based on the state of the view. */
  func configureControls() {
    print("configureControls \(playerState)")
    if playerState == .stopped {
      playButton.setImage(playImage, for: .normal)
      splashPlayButton.isHidden = false
      splashImage.layer.isHidden = false
      mediaPlayerLayer?.isHidden = true
      controlView.isHidden = true
    } else if playerState == .playing || playerState == .paused || playerState == .starting {
      // Play or Pause button based on state.
      let image: UIImage? = playerState == .paused ? playImage : pauseImage
      playButton.setImage(image, for: .normal)
      playButton.isHidden = false
      splashPlayButton.isHidden = true
      mediaPlayerLayer?.isHidden = false
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
    let frame: CGRect = fullFrame()
    // Play/Pause images.
    playImage = UIImage(named: "play")
    pauseImage = UIImage(named: "pause")
    // Toolbar.
    toolbarView = UIView()
    layoutToolbar(frame)
    // Background gradient
    gradientLayer = CAGradientLayer()
    gradientLayer?.frame = toolbarView.bounds
    gradientLayer?.colors = [(UIColor.clear.cgColor), (UIColor(red: (50 / 255.0), green: (50 / 255.0),
                                                               blue: (50 / 255.0), alpha: (200 / 255.0)).cgColor)]
    gradientLayer?.startPoint = CGPoint.zero
    gradientLayer?.endPoint = CGPoint(x: 0, y: 1)
    // Play/Pause button.
    playButton = UIButton(type: .system)
    playButton.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    playButton.setImage(playImage, for: .normal)
    playButton.addTarget(self, action: #selector(playButtonClicked), for: .touchUpInside)
    playButton.tintColor = UIColor.white
    playButton.translatesAutoresizingMaskIntoConstraints = false
    // Total time.
    totalTime = UILabel()
    totalTime.clearsContextBeforeDrawing = true
    totalTime.text = "00:00"
    totalTime.font = UIFont(name: "Helvetica", size: 14.0)
    totalTime.textColor = .white
    totalTime.tintColor = .white
    totalTime.translatesAutoresizingMaskIntoConstraints = false
    // Slider.
    slider = UISlider()
    let thumb = UIImage(named: "thumb")
    // TODO: new image
    slider.setThumbImage(thumb, for: .normal)
    slider.setThumbImage(thumb, for: .highlighted)
    slider.addTarget(self, action: #selector(onSliderValueChanged), for: .valueChanged)
    slider.addTarget(self, action: #selector(onSliderTouchStarted), for: .touchDown)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchUpInside)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchCancel)
    slider.addTarget(self, action: #selector(onSliderTouchEnded), for: .touchUpOutside)
    slider.autoresizingMask = .flexibleWidth
    slider.minimumValue = 0
    slider.minimumTrackTintColor = UIColor(red: (15.0 / 255), green: (153.0 / 255), blue: (242.0 / 255), alpha: 1.0)
    slider.translatesAutoresizingMaskIntoConstraints = false
    toolbarView.addSubview(playButton)
    toolbarView.addSubview(totalTime)
    toolbarView.addSubview(slider)
    if let gradientLayer = gradientLayer {
      toolbarView.layer.insertSublayer(gradientLayer, at: 0)
    }
    controlView.insertSubview(toolbarView, at: 0)
    activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
    activityIndicator.hidesWhenStopped = true
    controlView.insertSubview(activityIndicator, aboveSubview: toolbarView)
    // Layout.
    let hlayout: String = "|-[playButton(==40)]-5-[slider(>=120)]" +
      "-[totalTime(>=40)]-|"
    let vlayout: String = "V:|[playButton(==40)]"
    let viewsDictionary: [String: Any] = ["slider": slider, "totalTime": totalTime, "playButton": playButton]
    toolbarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: hlayout, options: .alignAllCenterY,
                                                              metrics: nil, views: viewsDictionary))
    toolbarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: vlayout,
                                                              options: [], metrics: nil, views: viewsDictionary))
  }

  /* Hide the tool bar, and the navigation controller if in the appropriate state.
   * If there has been a recent interaction, retry in kToolbarDelay seconds. */
  @objc func hideToolBar() {
    print("hideToolBar \(playerState)")
    if !(playerState == .playing || playerState == .starting) {
      return
    }
    if isRecentInteraction {
      isRecentInteraction = false
      perform(#selector(hideToolBar), with: self, afterDelay: TimeInterval(kToolbarDelay))
    } else {
      UIView.animate(withDuration: 0.5, animations: { () -> Void in
        self.toolbarView.alpha = 0
      }, completion: { (_: Bool) -> Void in
        self.hideControls()
        self.toolbarView.alpha = 1
      })
    }
  }

  /* Called when used touches the controlView. Display the controls, and if the
   * user is playing
   * set a timeout to hide them again. */
  @objc func didTouchControl(_: Any?) {
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
    mediaTimeObserver = mediaPlayer?.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1),
                                                             queue: nil, using: { [weak self] (_ time: CMTime) -> Void in
                                                               self?.notifyStreamPositionChanged(time)
    })
    NotificationCenter.default.addObserver(self, selector: #selector(handleMediaPlaybackEnded),
                                           name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                           object: mediaPlayer?.currentItem)
    mediaPlayer?.currentItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
    mediaPlayer?.currentItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
    mediaPlayer?.currentItem?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
    observingMediaPlayer = true
  }

  func removeMediaPlayerObservers() {
    print("removeMediaPlayerObservers")
    if observingMediaPlayer {
      if let mediaTimeObserverToRemove = mediaTimeObserver {
        mediaPlayer?.removeTimeObserver(mediaTimeObserverToRemove)
        mediaTimeObserver = nil
      }
      if mediaPlayer?.currentItem != nil {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                  object: mediaPlayer?.currentItem)
      }
      mediaPlayer?.currentItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
      mediaPlayer?.currentItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
      mediaPlayer?.currentItem?.removeObserver(self, forKeyPath: "status")
      observingMediaPlayer = false
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                             change _: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
    print("observeValueForKeyPath \(keyPath ?? "")")
    guard let currentItem = mediaPlayer?.currentItem, let object = object as? AVPlayerItem, object == currentItem else {
      return
    }
    if keyPath == "playbackLikelyToKeepUp" {
      activityIndicator.stopAnimating()
    } else if keyPath == "playbackBufferEmpty" {
      activityIndicator.startAnimating()
    } else if keyPath == "status" {
      if mediaPlayer?.status == .readyToPlay {
        handleMediaPlayerReady()
      }
    }
  }
}
