//
//  TerminalPaneController.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Combine
import CoreGraphics
import Foundation
import SwiftTerm

@MainActor
final class TerminalPaneController: ObservableObject {
    struct PendingViewportRestore {
        var normalScrollPosition: Double?
        var shouldSkipRestoreBecauseAlternateBufferWasActive: Bool
    }

    let paneID: PaneID
    let session: TerminalSession

    private weak var attachedTerminalView: LocalProcessTerminalView?
    private var retainedTerminalView: LocalProcessTerminalView?
    private var retainedTerminalGeneration: Int?
    private var startedTerminalGeneration: Int?

    init(paneID: PaneID, session: TerminalSession) {
        self.paneID = paneID
        self.session = session
    }

    func terminalView(
        for generation: Int,
        processDelegate: LocalProcessTerminalViewDelegate,
    ) -> LocalProcessTerminalView {
        if
            let terminalView = retainedTerminalView,
            retainedTerminalGeneration == generation {
            configureTerminalView(terminalView, processDelegate: processDelegate)
            return terminalView
        }

        let terminalView = LocalProcessTerminalView(frame: .zero)
        retainedTerminalView = terminalView
        retainedTerminalGeneration = generation
        startedTerminalGeneration = nil
        configureTerminalView(terminalView, processDelegate: processDelegate)
        return terminalView
    }

    func attach(terminalView: LocalProcessTerminalView) {
        attachedTerminalView = terminalView
    }

    func detach(terminalView: LocalProcessTerminalView) {
        guard attachedTerminalView === terminalView else {
            return
        }

        attachedTerminalView = nil
    }

    func needsProcessStart(for generation: Int) -> Bool {
        startedTerminalGeneration != generation
    }

    func markProcessStarted(for generation: Int) {
        startedTerminalGeneration = generation
    }

    func restoreHistoryIfNeeded(into terminalView: LocalProcessTerminalView) -> PendingViewportRestore? {
        guard let history = session.consumeRestoredHistory() else {
            return nil
        }

        if let transcript = history.transcript {
            let bytes = ArraySlice(Array(transcript.utf8))
            if !bytes.isEmpty {
                terminalView.feed(byteArray: bytes)
            }
        }

        let normalizedScrollPosition = history.normalScrollPosition.flatMap { scrollPosition in
            scrollPosition > 0 ? min(scrollPosition, 1) : nil
        }
        let shouldSkipRestoreBecauseAlternateBufferWasActive = history.wasAlternateBufferActive
        guard normalizedScrollPosition != nil || shouldSkipRestoreBecauseAlternateBufferWasActive else {
            return nil
        }

        return PendingViewportRestore(
            normalScrollPosition: normalizedScrollPosition,
            shouldSkipRestoreBecauseAlternateBufferWasActive: shouldSkipRestoreBecauseAlternateBufferWasActive,
        )
    }

    func captureHistory() -> WorkspaceSessionHistorySnapshot? {
        guard let terminalView = retainedTerminalView else {
            return nil
        }

        let terminal = terminalView.getTerminal()
        let transcript: String? = {
            let transcriptData = terminal.getBufferAsData(kind: .normal, encoding: .utf8)
            guard
                !transcriptData.isEmpty,
                let transcript = String(data: transcriptData, encoding: .utf8),
                !transcript.isEmpty
            else {
                return nil
            }

            return transcript
        }()
        let normalizedScrollPosition: Double? = {
            guard terminalView.canScroll else {
                return nil
            }

            let scrollPosition = terminalView.scrollPosition
            return scrollPosition > 0 ? min(scrollPosition, 1) : nil
        }()
        let wasAlternateBufferActive = terminal.isCurrentBufferAlternate
        let hasRestorableHistory = transcript != nil
            || normalizedScrollPosition != nil
            || wasAlternateBufferActive
        guard hasRestorableHistory else {
            return nil
        }

        return WorkspaceSessionHistorySnapshot(
            transcript: transcript,
            normalScrollPosition: normalizedScrollPosition,
            wasAlternateBufferActive: wasAlternateBufferActive,
        )
    }

    private func configureTerminalView(
        _ terminalView: LocalProcessTerminalView,
        processDelegate: LocalProcessTerminalViewDelegate,
    ) {
        terminalView.processDelegate = processDelegate
    }
}
