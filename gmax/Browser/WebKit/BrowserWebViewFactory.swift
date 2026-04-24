//
//  BrowserWebViewFactory.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation
import WebKit

@MainActor
final class BrowserWebView: WKWebView {
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onReload: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command] else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
            case "[":
                guard canGoBack else {
                    return super.performKeyEquivalent(with: event)
                }

                onGoBack?()
                return true

            case "]":
                guard canGoForward else {
                    return super.performKeyEquivalent(with: event)
                }

                onGoForward?()
                return true

            case "r", "R":
                onReload?()
                return true

            default:
                return super.performKeyEquivalent(with: event)
        }
    }
}

enum BrowserWebViewFactory {
    private static let sharedDataStore = WKWebsiteDataStore.default()

    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sharedDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = BrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}
