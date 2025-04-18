// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Foundation
import Shared
import Web
import WebKit

class HTTPBlockedScriptHandler: TabContentScript {
  private weak var tabManager: TabManager?

  required init(tabManager: TabManager) {
    self.tabManager = tabManager
  }

  static let scriptName = "HTTPBlockedScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page
  static let userScript: WKUserScript? = nil

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }

    if !verifyMessage(message: message, securityToken: UserScriptManager.securityToken) {
      assertionFailure("Missing required security token.")
      return
    }

    guard let params = message.body as? [String: AnyObject],
      let action = params["action"] as? String
    else {
      assertionFailure("Missing required params.")
      return
    }

    switch action {
    case "didProceed":
      didProceed(tab: tab)
    case "didGoBack":
      didGoBack(tab: tab)
    default:
      assertionFailure("Unhandled action `\(action)`")
    }
  }

  private func didProceed(tab: some TabState) {
    guard let url = tab.upgradedHTTPSRequest?.url ?? tab.visibleURL?.strippedInternalURL else {
      //      assertionFailure(
      //        "There should be no way this method can be triggered if the tab is not on an internal url"
      //      )
      return
    }

    // When restoring the page, `upgradedHTTPSRequest` will be nil
    // So we default to the embedded internal page URL
    let request = tab.upgradedHTTPSRequest ?? URLRequest(url: url)
    if let httpsUpgradeService = HttpsUpgradeServiceFactory.get(privateMode: tab.isPrivate),
      let host = url.host(percentEncoded: false)
    {
      httpsUpgradeService.allowHttp(forHost: host)
    }
    tab.loadRequest(request)
  }

  @MainActor private func didGoBack(tab: some TabState) {
    tab.upgradedHTTPSRequest = nil
    if tab.backForwardList?.backList.isEmpty == true {
      // interstitial was opened in a new tab
      tabManager?.addTabToRecentlyClosed(tab)
      tabManager?.removeTab(tab)
    } else {
      tab.goBack()
    }
  }
}
