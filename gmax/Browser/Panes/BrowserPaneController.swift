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
    private enum HistoryRestoreState {
        case replaying(items: [BrowserHistoryItemSnapshot], nextItemIndex: Int, targetCurrentIndex: Int)
        case returningToCurrent
    }

    let paneID: PaneID
    let session: BrowserSession

    private weak var attachedWebView: WKWebView?
    private var retainedWebView: WKWebView?
    private var didLoadInitialPage = false
    private var historyRestoreState: HistoryRestoreState?

    init(paneID: PaneID, session: BrowserSession) {
        self.paneID = paneID
        self.session = session
    }

    func webView() -> WKWebView {
        if let retainedWebView {
            return retainedWebView
        }

        let webView = BrowserWebViewFactory.makeWebView()
        if let browserWebView = webView as? BrowserWebView {
            browserWebView.onGoBack = { [weak self] in self?.goBack() }
            browserWebView.onGoForward = { [weak self] in self?.goForward() }
            browserWebView.onReload = { [weak self] in self?.reload() }
        }
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
        if restoreHistoryIfNeeded(in: webView) {
            return
        }

        let initialURLString = session.lastCommittedURL
            ?? session.url
            ?? BrowserNavigationDefaults.initialPageURLString()
        if let url = URL(string: initialURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    func continueHistoryRestoreIfNeeded(in webView: WKWebView) {
        guard let historyRestoreState else {
            return
        }

        switch historyRestoreState {
            case let .replaying(items, nextItemIndex, targetCurrentIndex):
                guard nextItemIndex < items.count else {
                    finishHistoryReplay(in: webView, itemsCount: items.count, targetCurrentIndex: targetCurrentIndex)
                    return
                }
                guard let nextURL = URL(string: items[nextItemIndex].url) else {
                    self.historyRestoreState = nil
                    return
                }

                self.historyRestoreState = .replaying(
                    items: items,
                    nextItemIndex: nextItemIndex + 1,
                    targetCurrentIndex: targetCurrentIndex,
                )
                webView.load(URLRequest(url: nextURL))

            case .returningToCurrent:
                self.historyRestoreState = nil
        }
    }

    func abortHistoryRestore() {
        historyRestoreState = nil
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

    func focusWebView() {
        guard let webView = attachedWebView ?? retainedWebView else {
            return
        }

        webView.window?.makeFirstResponder(webView)
    }

    private func restoreHistoryIfNeeded(in webView: WKWebView) -> Bool {
        guard let history = session.history else {
            return false
        }
        guard history.items.count > 1 else {
            return false
        }
        guard history.items.indices.contains(history.currentIndex) else {
            return false
        }
        guard let firstURL = URL(string: history.items[0].url) else {
            return false
        }
        guard history.items.dropFirst().allSatisfy({ URL(string: $0.url) != nil }) else {
            return false
        }

        historyRestoreState = .replaying(
            items: history.items,
            nextItemIndex: 1,
            targetCurrentIndex: history.currentIndex,
        )
        webView.load(URLRequest(url: firstURL))
        return true
    }

    private func finishHistoryReplay(
        in webView: WKWebView,
        itemsCount: Int,
        targetCurrentIndex: Int,
    ) {
        let finalIndex = itemsCount - 1
        let relativeOffset = targetCurrentIndex - finalIndex
        guard relativeOffset != 0 else {
            historyRestoreState = nil
            return
        }
        guard let targetItem = webView.backForwardList.item(at: relativeOffset) else {
            historyRestoreState = nil
            return
        }

        historyRestoreState = .returningToCurrent
        webView.go(to: targetItem)
    }
}
