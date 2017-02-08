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
import Foundation
import UIKit

class ActionSheetAction: NSObject {
  private(set) var title: String = ""

  override init(title: String, target: Any, selector: Selector) {
    super.init()

    self.title = title
    self.target = target
    self.selector = selector
  }

  func trigger() {
    if target && selector && target.responds(to: selector) {
      // See http://stackoverflow.com/questions/7017281
      var imp: IMP = target.method(for: selector)
      var () = (imp as? Void)
      func(target, selector)
    }
  }
  var target: Any!
  var selector = Selector()
}

class ActionSheet: NSObject, UIAlertViewDelegate {
  init(title: String, message: String, cancelButtonText: String) {
    super.init()
    title = title
    message = message
    cancelButtonText = cancelButtonText
    actions = [ActionSheetAction]()
  }

  func addAction(withTitle title: String, target: Any, selector: Selector) {
    var action = ActionSheetAction(title: title, target: target, selector: selector)
    actions.append(action)
  }

  func present(in parent: UIViewController, sourceView: UIView) {
    if UIAlertController.self {
      // iOS 8+ approach.
      var controller = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
      for action: ActionSheetAction in actions {
        var alertAction = UIAlertAction(title: action.title, style: .default, handler: {(_ unused: UIAlertAction) -> Void in
          action.trigger()
        })
        controller.addAction(alertAction)
      }
      if cancelButtonText {
        var cancelAction = UIAlertAction(title: cancelButtonText, style: .cancel, handler: {(_ action: UIAlertAction) -> Void in
          controller.dismiss(animated: true)
        })
        controller.addAction(cancelAction)
      }
      // Present the controller in the right location, on iPad. On iPhone, it
      // always displays at the
      // bottom of the screen.
      guard let presentationController = controller.popoverPresentationController { else return }
      presentationController.sourceView = sourceView
      presentationController.sourceRect = sourceView.bounds
      presentationController.permittedArrowDirections = 0
      parent.present(controller, animated: true)
    }
    else {
      // iOS 7 and below.
      var alertView = UIAlertView(title: title, message: message, delegate: self, cancelButtonTitle: cancelButtonText, otherButtonTitles: "")
      indexedActions = [AnyHashable: Any](minimumCapacity: actions.count)
      for action: ActionSheetAction in actions {
        var position: Int = alertView.addButton(withTitle: action.title)
        indexedActions[(position)] = action
      }
      alertView.show()
      // Hold onto this ActionSheet until the UIAlertView is dismissed. This
      // ensures that the delegate
      // is not released (as UIAlertView usually only holds a weak reference to
      // us).
      var kActionSheetKey: CChar
      objc_setAssociatedObject(alertView, kActionSheetKey, self, OBJC_ASSOCIATION_RETAIN)
    }
  }
  var title: String = ""
  var message: String = ""
  var cancelButtonText: String = ""
  var actions = [ActionSheetAction]()
  var indexedActions = [NSNumber: ActionSheetAction]()

  // MARK: - UIAlertViewDelegate

  func alertView(_ alertView: UIAlertView, clickedButtonat buttonIndex: Int) {
    indexedActions = nil
    var action: ActionSheetAction? = indexedActions[buttonIndex]
    action?.trigger()
  }

  func alertViewCancel(_ alertView: UIAlertView) {
    indexedActions = nil
  }
}
