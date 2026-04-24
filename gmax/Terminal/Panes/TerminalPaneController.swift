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
        var transcript: String?
        var normalScrollPosition: Double?
        var shouldSkipRestoreBecauseAlternateBufferWasActive: Bool
    }

    let paneID: PaneID
    let session: TerminalSession

    private weak var attachedTerminalView: LocalProcessTerminalView?
    private var retainedTerminalView: LocalProcessTerminalView?
    private var retainedTerminalGeneration: Int?
    private var startedTerminalGeneration: Int?
    private var capturedHostOutput = ""
    private var pendingHostOutputBytes: [UInt8] = []
    private var shellIntegrationParser = ShellIntegrationParser()

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

        let terminalView = HistoryRecordingTerminalView(frame: .zero)
        retainedTerminalView = terminalView
        retainedTerminalGeneration = generation
        startedTerminalGeneration = nil
        capturedHostOutput = ""
        pendingHostOutputBytes = []
        shellIntegrationParser = ShellIntegrationParser()
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

        let normalizedScrollPosition = history.normalScrollPosition.flatMap { scrollPosition in
            scrollPosition > 0 ? min(scrollPosition, 1) : nil
        }
        let shouldSkipRestoreBecauseAlternateBufferWasActive = history.wasAlternateBufferActive
        let transcript = history.transcript?.isEmpty == false ? history.transcript : nil
        guard transcript != nil || normalizedScrollPosition != nil || shouldSkipRestoreBecauseAlternateBufferWasActive else {
            return nil
        }

        return PendingViewportRestore(
            transcript: transcript,
            normalScrollPosition: normalizedScrollPosition,
            shouldSkipRestoreBecauseAlternateBufferWasActive: shouldSkipRestoreBecauseAlternateBufferWasActive,
        )
    }

    func captureHistory() -> WorkspaceSessionHistorySnapshot? {
        guard let terminalView = retainedTerminalView else {
            return nil
        }

        let terminal = terminalView.getTerminal()
        let hostTranscript = normalizedTranscript(capturedHostOutput)
        let dataTranscript = normalizedTranscript(
            String(data: terminal.getBufferAsData(kind: .normal, encoding: .utf8), encoding: .utf8),
        )
        let selectedTextTranscript = fullTerminalText(from: terminal)
        let transcript = preferredTranscript(
            hostTranscript: hostTranscript,
            dataTranscript: dataTranscript,
            selectedTextTranscript: selectedTextTranscript,
        )
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
        if let terminalView = terminalView as? HistoryRecordingTerminalView {
            terminalView.onHostOutput = { [weak self] slice in
                self?.appendHostOutput(slice)
            }
        }
    }

    private func fullTerminalText(from terminal: Terminal) -> String? {
        guard terminal.cols > 0 else {
            return nil
        }

        let start = Position(col: 0, row: 0)
        let end = Position(col: max(terminal.cols - 1, 0), row: Int.max)
        return normalizedTranscript(terminal.getText(start: start, end: end))
    }

    private func normalizedTranscript(_ transcript: String?) -> String? {
        guard let transcript, !transcript.isEmpty else {
            return nil
        }

        return transcript
    }

    private func preferredTranscript(
        hostTranscript: String?,
        dataTranscript: String?,
        selectedTextTranscript: String?,
    ) -> String? {
        let hostScore = transcriptSignalScore(hostTranscript)
        let selectedScore = transcriptSignalScore(selectedTextTranscript)
        let dataScore = transcriptSignalScore(dataTranscript)
        if hostScore >= selectedScore, hostScore >= dataScore {
            return hostTranscript ?? selectedTextTranscript ?? dataTranscript
        }
        return selectedScore >= dataScore ? selectedTextTranscript ?? dataTranscript : dataTranscript
    }

    private func transcriptSignalScore(_ transcript: String?) -> Int {
        guard let transcript else {
            return 0
        }

        return transcript.unicodeScalars.reduce(into: 0) { count, scalar in
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                count += 1
            }
        }
    }

    private func appendHostOutput(_ slice: ArraySlice<UInt8>) {
        guard !slice.isEmpty else {
            return
        }

        let shellIntegrationEvents = shellIntegrationParser.ingest(slice)
        for event in shellIntegrationEvents {
            session.applyShellIntegrationEvent(event)
        }

        let combinedBytes = pendingHostOutputBytes + slice
        let decodedByteCount = largestDecodableUTF8PrefixLength(in: combinedBytes)
        if decodedByteCount > 0,
           let decodedPrefix = String(bytes: combinedBytes.prefix(decodedByteCount), encoding: .utf8) {
            capturedHostOutput += decodedPrefix
        }
        pendingHostOutputBytes = Array(combinedBytes.dropFirst(decodedByteCount).suffix(4))
        let maxTranscriptCharacters = 250_000
        if capturedHostOutput.count > maxTranscriptCharacters {
            capturedHostOutput = String(capturedHostOutput.suffix(maxTranscriptCharacters))
        }
    }

    private func largestDecodableUTF8PrefixLength(in bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else {
            return 0
        }

        for prefixLength in stride(from: bytes.count, through: 1, by: -1) {
            if String(bytes: bytes.prefix(prefixLength), encoding: .utf8) != nil {
                return prefixLength
            }
        }
        return 0
    }
}

private final class HistoryRecordingTerminalView: LocalProcessTerminalView {
    var onHostOutput: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onHostOutput?(slice)
        super.dataReceived(slice: slice)
    }
}
