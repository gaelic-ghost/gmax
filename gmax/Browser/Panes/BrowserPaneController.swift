//
//  BrowserPaneController.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation
import WebKit

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
        let initialURLString = session.lastCommittedURL ?? session.url
        if let initialURLString,
           let url = URL(string: initialURLString) {
            webView.load(URLRequest(url: url))
        } else if let url = URL(string: "about:blank") {
            webView.load(URLRequest(url: url))
        }
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
