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

import GoogleCast
import UIKit

let kCastControlBarsAnimationDuration: TimeInterval = 0.20

@objc(RootContainerViewController)
class RootContainerViewController: UIViewController, GCKUIMiniMediaControlsViewControllerDelegate {
  @IBOutlet private var _miniMediaControlsContainerView: UIView!
  @IBOutlet private var _miniMediaControlsHeightConstraint: NSLayoutConstraint!
  private var miniMediaControlsViewController: GCKUIMiniMediaControlsViewController!
  var miniMediaControlsViewEnabled = false {
    didSet {
      if isViewLoaded {
        updateControlBarsVisibility()
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
    miniMediaControlsViewController = castContext.createMiniMediaControlsViewController()
    miniMediaControlsViewController.delegate = self
    updateControlBarsVisibility()
    installViewController(miniMediaControlsViewController,
                          inContainerView: _miniMediaControlsContainerView)
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  // MARK: - Internal methods

  func updateControlBarsVisibility() {
    if miniMediaControlsViewEnabled, miniMediaControlsViewController.active {
      _miniMediaControlsHeightConstraint.constant = miniMediaControlsViewController.minHeight
      view.bringSubviewToFront(_miniMediaControlsContainerView)
    } else {
      _miniMediaControlsHeightConstraint.constant = 0
    }
    UIView.animate(withDuration: kCastControlBarsAnimationDuration, animations: { () -> Void in
      self.view.layoutIfNeeded()
    })
    view.setNeedsLayout()
  }

  func installViewController(_ viewController: UIViewController?, inContainerView containerView: UIView) {
    if let viewController = viewController {
      addChild(viewController)
      viewController.view.frame = containerView.bounds
      containerView.addSubview(viewController.view)
      viewController.didMove(toParent: self)
    }
  }

  func uninstallViewController(_ viewController: UIViewController) {
    viewController.willMove(toParent: nil)
    viewController.view.removeFromSuperview()
    viewController.removeFromParent()
  }

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    if segue.identifier == "NavigationVCEmbedSegue" {
      navigationController = (segue.destination as? UINavigationController)
    }
  }

  // MARK: - GCKUIMiniMediaControlsViewControllerDelegate

  func miniMediaControlsViewController(_: GCKUIMiniMediaControlsViewController,
                                       shouldAppear _: Bool) {
    updateControlBarsVisibility()
  }
}
