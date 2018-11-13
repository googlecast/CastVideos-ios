// Copyright 2018 Google Inc. All Rights Reserved.
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

@objc(RootContainerViewController)
class RootContainerViewController: UIViewController, GCKUIMiniMediaControlsViewControllerDelegate {

  @IBOutlet weak private var _miniMediaControlsContainerView: UIView!
  @IBOutlet weak private var _miniMediaControlsHeightConstraint: NSLayoutConstraint!
  private var miniMediaControlsViewController: GCKUIMiniMediaControlsViewController!
  var miniMediaControlsViewEnabled = false {
    didSet {
      if self.isViewLoaded {
        self.updateControlBarsVisibility()
      }
    }
  }

  var overridenNavigationController: UINavigationController?

  override var navigationController: UINavigationController? {

    get {
      return overridenNavigationController
    }

    set {
      overridenNavigationController = newValue
    }
  }
  var miniMediaControlsItemEnabled = false

  override func viewDidLoad() {
    super.viewDidLoad()
    let castContext = GCKCastContext.sharedInstance()
    self.miniMediaControlsViewController = castContext.createMiniMediaControlsViewController()
    self.miniMediaControlsViewController.delegate = self
    self.updateControlBarsVisibility()
    self.installViewController(self.miniMediaControlsViewController,
                               inContainerView: self._miniMediaControlsContainerView)
  }
  // MARK: - Internal methods

  func updateControlBarsVisibility() {
    if self.miniMediaControlsViewEnabled && self.miniMediaControlsViewController.active {
      self._miniMediaControlsHeightConstraint.constant = self.miniMediaControlsViewController.minHeight
      self.view.bringSubview(toFront: self._miniMediaControlsContainerView)
    } else {
      self._miniMediaControlsHeightConstraint.constant = 0
    }
    UIView.animate(withDuration: kCastControlBarsAnimationDuration, animations: {() -> Void in
      self.view.layoutIfNeeded()
    })
    self.view.setNeedsLayout()
  }

  func installViewController(_ viewController: UIViewController?, inContainerView containerView: UIView) {
    if let viewController = viewController {
      self.addChildViewController(viewController)
      viewController.view.frame = containerView.bounds
      containerView.addSubview(viewController.view)
      viewController.didMove(toParentViewController: self)
    }
  }

  func uninstallViewController(_ viewController: UIViewController) {
    viewController.willMove(toParentViewController: nil)
    viewController.view.removeFromSuperview()
    viewController.removeFromParentViewController()
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "NavigationVCEmbedSegue" {
      self.navigationController = (segue.destination as? UINavigationController)
    }
  }
  // MARK: - GCKUIMiniMediaControlsViewControllerDelegate

  func miniMediaControlsViewController(_ miniMediaControlsViewController: GCKUIMiniMediaControlsViewController,
                                       shouldAppear: Bool) {
    self.updateControlBarsVisibility()
  }
}
