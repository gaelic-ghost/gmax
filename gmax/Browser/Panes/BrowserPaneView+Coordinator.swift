//
//  BrowserPaneView+Coordinator.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import AppKit
import Foundation
import OSLog
import WebKit

extension BrowserPaneView {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: BrowserPaneController
        let openExternalURL: (URL) -> Void

        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?

        init(
            controller: BrowserPaneController,
            openExternalURL: @escaping (URL) -> Void,
        ) {
            self.controller = controller
            self.openExternalURL = openExternalURL
        }

        func makeHostingView() -> BrowserPaneHostView {
            let webView = controller.webView()
            configure(webView)
            controller.attach(webView: webView)
            let hostingView = BrowserPaneHostView(webView: webView)
            controller.loadInitialPageIfNeeded(in: webView)
            return hostingView
        }

        func update(hostingView: BrowserPaneHostView) {
            configure(hostingView.webView)
            controller.loadInitialPageIfNeeded(in: hostingView.webView)
        }

        func dismantle(hostingView: BrowserPaneHostView) {
            titleObservation = nil
            urlObservation = nil
            loadingObservation = nil
            canGoBackObservation = nil
            canGoForwardObservation = nil
            hostingView.webView.navigationDelegate = nil
            controller.detach(webView: hostingView.webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller.session.state = .loading
            updateNavigationSnapshot(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller.session.state = .idle
            controller.session.lastCommittedURL = webView.url?.absoluteString
            updateNavigationSnapshot(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error,
        ) {
            handleNavigationFailure(error, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error,
        ) {
            handleNavigationFailure(error, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let paneID = controller.paneID.rawValue.uuidString
            Logger.pane.error("A browser pane lost its WebKit web-content process and needs a reload. Pane ID: \(paneID, privacy: .public)")
            controller.session.state = .failed("Browser content process terminated. Reload the page to continue.")
            updateNavigationSnapshot(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void,
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if shouldOpenExternally(url) {
                openExternalURL(url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func configure(_ webView: WKWebView) {
            guard webView.navigationDelegate !== self else {
                return
            }

            webView.navigationDelegate = self
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.controller.session.title = webView.title?.isEmpty == false ? webView.title ?? "Browser" : "Browser"
                }
            }
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.controller.session.url = webView.url?.absoluteString
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.controller.session.state = webView.isLoading ? .loading : .idle
                }
            }
            canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.controller.session.canGoBack = webView.canGoBack
                }
            }
            canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.controller.session.canGoForward = webView.canGoForward
                }
            }
        }

        private func updateNavigationSnapshot(from webView: WKWebView) {
            controller.session.title = webView.title?.isEmpty == false ? webView.title ?? "Browser" : "Browser"
            controller.session.url = webView.url?.absoluteString
            controller.session.canGoBack = webView.canGoBack
            controller.session.canGoForward = webView.canGoForward
        }

        private func handleNavigationFailure(_ error: Error, in webView: WKWebView) {
            let paneID = controller.paneID.rawValue.uuidString
            Logger.pane.error("A browser pane navigation failed. Pane ID: \(paneID, privacy: .public). Error: \(String(describing: error), privacy: .public)")
            controller.session.state = .failed("Browser navigation failed: \(error.localizedDescription)")
            updateNavigationSnapshot(from: webView)
        }

        private func shouldOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }

            return !["http", "https", "about", "file"].contains(scheme)
        }
    }
}
