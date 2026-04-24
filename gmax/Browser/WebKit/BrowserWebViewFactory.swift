//
//  BrowserWebViewFactory.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation
import WebKit

enum BrowserWebViewFactory {
    private static let sharedDataStore = WKWebsiteDataStore.default()

    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sharedDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}
