// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import AIChat
import BraveCore
import BraveShared
import BraveStore
import BraveVPN
import Foundation
import Preferences
import Shared
import Web
import WebKit
import os.log

class BraveSkusScriptHandler: TabContentScript {
  static let scriptName = "BraveSkusScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page
  static let userScript: WKUserScript? = {
    guard var script = loadUserScript(named: scriptName) else {
      return nil
    }

    return WKUserScript(
      source: secureScript(
        handlerNamesMap: ["$<message_handler>": messageHandlerName]
          .merging(Method.map, uniquingKeysWith: { $1 }),
        securityToken: scriptId,
        script: script
      ),
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true,
      in: scriptSandbox
    )
  }()

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    if !verifyMessage(message: message) {
      assertionFailure("Missing required security token.")
      return
    }

    // Validate that we can handle this message
    guard let requestHost = try? RequestHost.from(message: message) else {
      return
    }

    guard let response = message.body as? [String: Any] else {
      Logger.module.error("Brave skus request with no message")
      return
    }

    guard let requestedMethod = response["method_id"] as? String,
      let method = Method(rawValue: requestedMethod)
    else {
      Logger.module.error("Brave skus request with invalid method-id")
      return
    }

    Task { @MainActor in
      do {
        let result = try await processRequest(
          tab: tab,
          message: message,
          method: method,
          for: requestHost
        )
        replyHandler(result, nil)
      } catch {
        Logger.module.error("Brave skus error processing request: \(error)")
        replyHandler(nil, nil)
      }
    }
  }

  @MainActor
  private func processRequest(
    tab: some TabState,
    message: WKScriptMessage,
    method: Method,
    for skusDomain: String
  ) async throws -> Any? {
    guard let skusManager = BraveSkusManager(isPrivateMode: tab.isPrivate) else {
      return nil
    }

    switch method {
    case .refreshOrder:
      let order = try OrderMessage.from(message: message)
      return await skusManager.refreshOrder(for: order.orderId, domain: skusDomain)

    case .fetchOrderCredentials:
      let order = try OrderMessage.from(message: message)
      return await skusManager.fetchOrderCredentials(for: order.orderId, domain: skusDomain)

    case .prepareCredentialsPresentation:
      Logger.module.error(
        "Error - Website calling prepareCredentialsPresentation when it shouldn't"
      )
      return nil

    case .credentialsSummary:
      let summary = try CredentialSummaryMessage.from(message: message)
      return await skusManager.credentialSummary(for: summary.domain)

    case .setLocalStorageReceipt:
      let storeMessage = try StoreReceiptMessage.from(message: message)
      if storeMessage.message == "vpn" {
        if let vpnSubscriptionProductId = Preferences.VPN.subscriptionProductId.value,
          let product = BraveStoreProduct(rawValue: vpnSubscriptionProductId)
        {
          let storageKey = product.localStorageKey
          let receipt = try BraveSkusSDK.receipt(for: product)
          return ["key": storageKey, "data": receipt]
        }
      }

      if storeMessage.message == "leo" {
        if let aiChatSubscriptionProductId = Preferences.AIChat.subscriptionProductId.value,
          let orderId = Preferences.AIChat.subscriptionOrderId.value,
          let product = BraveStoreProduct(rawValue: aiChatSubscriptionProductId)
        {
          let storageKey = product.localStorageKey
          let receipt = try BraveSkusSDK.receipt(for: product)
          return ["key": storageKey, "data": receipt, "braveLeo.orderId": orderId]
        }
      }
      throw SkusWebMessageError.invalidFormat
    }
  }
}

extension BraveSkusScriptHandler {
  private enum Method: String, CaseIterable {
    case refreshOrder
    case fetchOrderCredentials
    case prepareCredentialsPresentation
    case credentialsSummary
    case setLocalStorageReceipt

    static var map: [String: String] {
      var jsDict = [String: String]()
      allCases.forEach({
        jsDict.updateValue("\($0.rawValue)", forKey: "$<\($0)>")
      })
      return jsDict
    }
  }

  private struct OrderMessage: SkusWebMessage {
    let orderId: String
  }

  private struct CredentialsMessage: SkusWebMessage {
    let domain: String
    let path: String
  }

  private struct CredentialSummaryMessage: SkusWebMessage {
    let domain: String
  }

  private struct StoreReceiptMessage: SkusWebMessage {
    let message: String
  }
}

private enum SkusWebMessageError: Error {
  case invalidFormat
  case invalidRequestHost
  case invalidRequestFrame
}

private protocol SkusWebMessage: Codable {
  static func from(message: WKScriptMessage) throws -> Self
}

extension SkusWebMessage {
  static func from(message: WKScriptMessage) throws -> Self {
    guard let body = message.body as? [String: Any] else {
      throw SkusWebMessageError.invalidFormat
    }

    guard let messageData = body["data"] else {
      throw SkusWebMessageError.invalidFormat
    }

    let data = try JSONSerialization.data(withJSONObject: messageData)
    return try JSONDecoder().decode(Self.self, from: data)
  }
}

struct RequestHost {
  static func from(message: WKScriptMessage) throws -> String {
    guard message.frameInfo.isMainFrame else {
      Logger.module.error(
        "Brave skus request with error: \(SkusWebMessageError.invalidRequestFrame)"
      )
      throw SkusWebMessageError.invalidRequestFrame
    }

    guard let requestHost = message.frameInfo.request.url?.host else {
      Logger.module.error(
        "Brave skus request with error: \(SkusWebMessageError.invalidRequestHost)"
      )
      throw SkusWebMessageError.invalidRequestHost
    }

    guard DomainUserScript.braveSkus.associatedDomains.contains(requestHost) else {
      Logger.module.error(
        "Brave skus request with error: \(SkusWebMessageError.invalidRequestHost)"
      )
      throw SkusWebMessageError.invalidRequestHost
    }

    return requestHost
  }
}
