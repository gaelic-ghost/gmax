//
//  BrowserPaneController.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation
import WebKit

enum BrowserNavigationDefaults {
    nonisolated static let homePageURLKey = "browserNavigation.homePageURL"

    nonisolated static func configuredHomePageURLString(
        userDefaults: UserDefaults = .standard,
    ) -> String? {
        normalizedNavigationURLString(
            from: userDefaults.string(forKey: homePageURLKey) ?? "",
        )
    }

    nonisolated static func normalizedNavigationURLString(from value: String) -> String? {
        normalizedNavigationURL(from: value)?.absoluteString
    }

    nonisolated static func normalizedNavigationURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let directURL = URL(string: trimmedValue),
           let scheme = directURL.scheme?.lowercased(),
           ["http", "https", "about", "file"].contains(scheme) {
            return directURL
        }

        guard !trimmedValue.contains(where: \.isWhitespace) else {
            return nil
        }

        let inferredScheme = inferredSchemeForSchemeLessValue(trimmedValue)
        return URL(string: "\(inferredScheme)://\(trimmedValue)")
    }

    nonisolated static func initialPageURLString(
        userDefaults: UserDefaults = .standard,
    ) -> String {
        configuredHomePageURLString(userDefaults: userDefaults) ?? "about:blank"
    }

    private nonisolated static func inferredSchemeForSchemeLessValue(_ value: String) -> String {
        let lowercasedValue = value.lowercased()
        if lowercasedValue.hasPrefix("localhost")
            || lowercasedValue.hasPrefix("127.0.0.1")
            || lowercasedValue.hasPrefix("0.0.0.0")
            || lowercasedValue.hasPrefix("[::1]") {
            return "http"
        }

        return "https"
    }
}

@MainActor
final class BrowserPaneController {
    let paneID: PaneID
    let session: BrowserSession

    private weak var attachedWebView: WKWebView?
    private var retainedWebView: WKWebView?
    private var didLoadInitialPage = false

    init(paneID: PaneID, session: BrowserSession) {
        self.paneID = paneID
        self.session = session
    }

    func webView() -> WKWebView {
        if let retainedWebView {
            return retainedWebView
        }

        let webView = BrowserWebViewFactory.makeWebView()
        retainedWebView = webView
        return webView
    }

    func attach(webView: WKWebView) {
        attachedWebView = webView
    }

    func detach(webView: WKWebView) {
        guard attachedWebView === webView else {
            return
        }

        attachedWebView = nil
    }

    func loadInitialPageIfNeeded(in webView: WKWebView) {
        guard !didLoadInitialPage else {
            return
        }

        didLoadInitialPage = true
        let initialURLString = session.lastCommittedURL
            ?? session.url
            ?? BrowserNavigationDefaults.initialPageURLString()
        if let url = URL(string: initialURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    func loadAddress(_ value: String) {
        guard let url = BrowserNavigationDefaults.normalizedNavigationURL(from: value) else {
            return
        }

        retainedWebView?.load(URLRequest(url: url))
    }

    func goHome() {
        loadAddress(BrowserNavigationDefaults.initialPageURLString())
    }

    func reload() {
        retainedWebView?.reload()
    }

    func goBack() {
        retainedWebView?.goBack()
    }

    func goForward() {
        retainedWebView?.goForward()
    }

    func stopLoading() {
        retainedWebView?.stopLoading()
    }
}
