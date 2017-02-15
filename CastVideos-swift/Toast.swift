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
// Coordinate to ensure two toasts are never active at once.
var isToastActive: Bool = false

var activeToast: Toast?

class Toast: UIView {

  var messageLabel: UILabel!
  class func displayMessage(_ message: String, for timeInterval: TimeInterval, in view: UIView) {
    if !isToastActive {
      isToastActive = true
      // Compute toast frame dimensions.
      var hostHeight: CGFloat = view.frame.size.height
      var hostWidth: CGFloat = view.frame.size.width
      var horizontalOffset: CGFloat = 0
      var toastHeight: CGFloat = 48
      var toastWidth: CGFloat = hostWidth
      var verticalOffset: CGFloat = hostHeight - toastHeight
      var toastRect = CGRect(x: horizontalOffset, y: verticalOffset, width: toastWidth, height: toastHeight)
      // Init and stylize the toast and message.
      var toast = Toast(frame: toastRect)
      toast.backgroundColor = UIColor(red: CGFloat((50 / 255.0)), green: CGFloat((50 / 255.0)), blue: CGFloat((50 / 255.0)), alpha: CGFloat(1))
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
      NotificationCenter.default.addObserver(self, selector: #selector(self.orientationChanged), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
      // Set the toast's timeout
      DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(timeInterval * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {() -> Void in
        toast.removeFromSuperview()
        NotificationCenter.default.removeObserver(self)
        isToastActive = false
        activeToast = nil
      })
    }
  }


  override init(frame: CGRect) {
    return super.init(frame: frame)
  }

  override func touchesEnded(_ touches: Set<UITouch>, withEvent event: UIEvent?) {
    self.removeFromSuperview()
    isToastActive = false
  }

  class func orientationChanged(_ notification: Notification) {
    if isToastActive {
      activeToast?.removeFromSuperview()
      isToastActive = false
    }
  }
}
