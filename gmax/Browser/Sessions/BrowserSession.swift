//
//  BrowserSession.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Combine
import Foundation

enum BrowserSessionState: Equatable {
    case idle
    case loading
    case failed(String)
}

@MainActor
final class BrowserSession: ObservableObject, Identifiable {
    let id: BrowserSessionID

    @Published var title: String
    @Published var url: String?
    @Published var lastCommittedURL: String?
    @Published var state: BrowserSessionState
    @Published var canGoBack: Bool
    @Published var canGoForward: Bool

    init(
        id: BrowserSessionID,
        title: String = "Browser",
        url: String? = nil,
        lastCommittedURL: String? = nil,
        state: BrowserSessionState = .idle,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.lastCommittedURL = lastCommittedURL
        self.state = state
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    convenience init(snapshot: BrowserSessionSnapshot) {
        let restoredState: BrowserSessionState
        switch snapshot.state {
            case .idle:
                restoredState = .idle
            case .loading:
                restoredState = .loading
            case .failed:
                restoredState = .failed(snapshot.failureDescription ?? "Browser navigation failed.")
        }
        self.init(
            id: snapshot.id,
            title: snapshot.title,
            url: snapshot.url,
            lastCommittedURL: snapshot.lastCommittedURL,
            state: restoredState,
            canGoBack: false,
            canGoForward: false,
        )
    }

    func makeSnapshot() -> BrowserSessionSnapshot {
        let failureDescription: String?
        switch state {
            case let .failed(message):
                failureDescription = message
            case .idle, .loading:
                failureDescription = nil
        }
        let snapshotState: BrowserSessionSnapshotState
        switch state {
            case .idle:
                snapshotState = .idle
            case .loading:
                snapshotState = .loading
            case .failed:
                snapshotState = .failed
        }
        let trimmedPreviewText = (lastCommittedURL ?? url)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let previewText = trimmedPreviewText?.isEmpty == false ? trimmedPreviewText : nil

        return BrowserSessionSnapshot(
            id: id,
            title: title,
            url: url,
            lastCommittedURL: lastCommittedURL,
            state: snapshotState,
            failureDescription: failureDescription,
            previewText: previewText,
        )
    }
}
