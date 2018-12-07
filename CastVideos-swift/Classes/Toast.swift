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

import UIKit

// Coordinate to ensure two toasts are never active at once.
var isToastActive: Bool = false
var activeToast: Toast?

class Toast: UIView {
  var messageLabel: UILabel!
  class func displayMessage(_ message: String, for timeInterval: TimeInterval, in view: UIView?) {
    guard let view = view else { return }
    if !isToastActive {
      isToastActive = true
      // Compute toast frame dimensions.
      let hostHeight: CGFloat = view.frame.size.height
      let hostWidth: CGFloat = view.frame.size.width
      let horizontalOffset: CGFloat = 0
      let toastHeight: CGFloat = 48
      let toastWidth: CGFloat = hostWidth
      let verticalOffset: CGFloat = hostHeight - toastHeight
      let toastRect = CGRect(x: horizontalOffset, y: verticalOffset, width: toastWidth, height: toastHeight)
      // Init and stylize the toast and message.
      let toast = Toast(frame: toastRect)
      toast.backgroundColor = UIColor(red: CGFloat((50 / 255.0)), green: CGFloat((50 / 255.0)),
                                      blue: CGFloat((50 / 255.0)), alpha: CGFloat(1))
      toast.messageLabel = UILabel(frame: CGRect(x: CGFloat(0), y: CGFloat(0), width: toastWidth, height: toastHeight))
      toast.messageLabel.text = message
      toast.messageLabel.textColor = UIColor.white
      toast.messageLabel.textAlignment = .center
      toast.messageLabel.font = UIFont.systemFont(ofSize: CGFloat(18))
      toast.messageLabel.adjustsFontSizeToFitWidth = true
      // Put the toast on top of the host view.
      toast.addSubview(toast.messageLabel)
      view.insertSubview(toast, aboveSubview: view.subviews.last!)
      activeToast = toast
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
                                             name: UIDevice.orientationDidChangeNotification, object: nil)
      // Set the toast's timeout
      DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() +
        Double(Int64(timeInterval * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: { () -> Void in
          toast.removeFromSuperview()
          NotificationCenter.default.removeObserver(self)
          isToastActive = false
          activeToast = nil
      })
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
    removeFromSuperview()
    isToastActive = false
  }

  @objc class func orientationChanged(_: Notification) {
    if isToastActive {
      activeToast?.removeFromSuperview()
      isToastActive = false
    }
  }
}
