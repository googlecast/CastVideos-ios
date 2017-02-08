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
import UIKit
let kCastControlBarsAnimationDuration: TimeInterval = 0.20

class RootContainerViewController: UIViewController, GCKUIMiniMediaControlsViewControllerDelegate {


  @IBOutlet weak var miniMediaControlsContainerView: UIView!
  @IBOutlet weak var miniMediaControlsHeightConstraint: NSLayoutConstraint!
  var miniMediaControlsViewController: GCKUIMiniMediaControlsViewController!
  weak var navigationController: UINavigationController?
  var isMiniMediaControlsViewEnabled: Bool {
    get {
      // TODO: add getter implementation
    }
    set(miniMediaControlsViewEnabled) {
      self.isMiniMediaControlsViewEnabled = isMiniMediaControlsViewEnabled
      if self.isViewLoaded() {
        self.updateControlBarsVisibility()
      }
    }
  }
  weak private(set) var navigationController: UINavigationController?
  var isMiniMediaControlsItemEnabled: Bool = false


  override func viewDidLoad() {
    super.viewDidLoad()
    var castContext = GCKCastContext.sharedInstance()
    self.miniMediaControlsViewController = castContext.createMiniMediaControlsViewController()
    self.miniMediaControlsViewController.delegate = self
    self.updateControlBarsVisibility()
    self.installViewController(self.miniMediaControlsViewController, inContainerView: self.miniMediaControlsContainerView)
  }
  // MARK: - Internal methods

  func updateControlBarsVisibility() {
    if self.isMiniMediaControlsViewEnabled && self.miniMediaControlsViewController.active {
      self.miniMediaControlsHeightConstraint.constant = self.miniMediaControlsViewController.minHeight
      self.view.bringSubview(toFront: self.miniMediaControlsContainerView)
    }
    else {
      self.miniMediaControlsHeightConstraint.constant = 0
    }
    UIView.animate(withDuration: kCastControlBarsAnimationDuration, animations: {() -> Void in
      self.view.layoutIfNeeded()
    })
    self.view.setNeedsLayout()
  }

  func installViewController(_ viewController: UIViewController, inContainerView containerView: UIView) {
    if viewController {
      self.addChildViewController(viewController)
      viewController.view.frame = containerView.bounds
      containerView.addSubview(viewController.view)
      viewController.didMove(toParentViewController: self)
    }
  }

  func uninstallViewController(_ viewController: UIViewController) {
    viewController.willMove(toParentViewController: nil)
    viewController.view.removeFromSuperview()
    viewController.removeFromParent()
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if (segue.identifier == "NavigationVCEmbedSegue") {
      self.navigationController = (segue.destination as? UINavigationController)
    }
  }
  // MARK: - GCKUIMiniMediaControlsViewControllerDelegate

  func miniMediaControlsViewController(_ miniMediaControlsViewController: GCKUIMiniMediaControlsViewController, shouldAppear: Bool) {
    self.updateControlBarsVisibility()
  }
}
