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

import Foundation
import UIKit

class ActionSheetAction: NSObject {
  fileprivate(set) var title: String?
  private var target: AnyObject?
  private var selector: Selector?

  init(title: String, target: AnyObject, selector: Selector) {
    super.init()

    self.title = title
    self.target = target
    self.selector = selector
  }

  func trigger() {
    if let target = target, let selector = selector, target.responds(to: selector) {
      _ = target.perform(selector)
    }
  }
}

class ActionSheet: NSObject, UIAlertViewDelegate {
  var title: String?
  var message: String?
  var cancelButtonText: String?
  var actions: [ActionSheetAction]!
  var indexedActions: [Int: ActionSheetAction]?

  init(title: String, message: String, cancelButtonText: String) {
    super.init()
    self.title = title
    self.message = message
    self.cancelButtonText = cancelButtonText
    actions = [ActionSheetAction]()
  }

  func addAction(withTitle title: String, target: AnyObject, selector: Selector) {
    let action = ActionSheetAction(title: title, target: target, selector: selector)
    actions.append(action)
  }

  func present(in parent: UIViewController, sourceView: UIView) {
    if objc_getClass("UIAlertController") != nil {
      // iOS 8+ approach.
      let controller = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
      for action: ActionSheetAction in actions {
        let alertAction = UIAlertAction(title: action.title,
                                        style: .default, handler: { (_: UIAlertAction) -> Void in
                                          action.trigger()
        })
        controller.addAction(alertAction)
      }
      if let cancelButtonText = cancelButtonText {
        let cancelAction = UIAlertAction(title: cancelButtonText, style: .cancel,
                                         handler: { (_: UIAlertAction) -> Void in
                                           controller.dismiss(animated: true)
        })
        controller.addAction(cancelAction)
      }
      // Present the controller in the right location, on iPad. On iPhone, it
      // always displays at the
      // bottom of the screen.
      if let presentationController = controller.popoverPresentationController {
        presentationController.sourceView = sourceView
        presentationController.sourceRect = sourceView.bounds
        presentationController.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
      }
      parent.present(controller, animated: true)
    } else {
      // iOS 7 and below.
      let alertView = UIAlertView(title: title ?? "",
                                  message: message ?? "",
                                  delegate: self,
                                  cancelButtonTitle: cancelButtonText,
                                  otherButtonTitles: "")
      indexedActions = [AnyHashable: Any](minimumCapacity: actions.count) as? [Int: ActionSheetAction]
      for action: ActionSheetAction in actions {
        let position = alertView.addButton(withTitle: action.title)
        indexedActions?[position] = action
      }
      alertView.show()
      // Hold onto this ActionSheet until the UIAlertView is dismissed. This
      // ensures that the delegate is not released (as UIAlertView usually only
      // holds a weak reference to us).
      objc_setAssociatedObject(alertView, "", self, .OBJC_ASSOCIATION_RETAIN)
    }
  }

  // MARK: - UIAlertViewDelegate

  func alertView(_: UIAlertView, clickedButtonAt buttonIndex: Int) {
    let action: ActionSheetAction? = indexedActions?[buttonIndex]
    action?.trigger()
  }

  func alertViewCancel(_: UIAlertView) {
    indexedActions = nil
  }
}
