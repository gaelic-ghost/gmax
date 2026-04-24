//
//  TerminalSession.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Combine
import Foundation

enum TerminalSessionState: Equatable {
    case idle
    case running
    case exited(Int32?)
}

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: TerminalSessionID
    let launchConfiguration: TerminalLaunchConfiguration

    @Published var title: String
    @Published var currentDirectory: String?
    @Published var state: TerminalSessionState
    @Published private(set) var relaunchGeneration: Int

    private var pendingRestoredHistory: WorkspaceSessionHistorySnapshot?

    init(
        id: TerminalSessionID,
        launchConfiguration: TerminalLaunchConfiguration = .loginShell,
        title: String = "Shell",
        currentDirectory: String? = nil,
        state: TerminalSessionState = .idle,
        relaunchGeneration: Int = 0,
    ) {
        self.id = id
        self.launchConfiguration = launchConfiguration
        self.title = title
        self.currentDirectory = currentDirectory
        self.state = state
        self.relaunchGeneration = relaunchGeneration
    }

    func prepareForRelaunch() {
        title = "Shell"
        currentDirectory = launchConfiguration.currentDirectory
        state = .idle
        pendingRestoredHistory = nil
        relaunchGeneration += 1
    }

    func setRestoredHistory(_ history: WorkspaceSessionHistorySnapshot?) {
        guard let history else {
            pendingRestoredHistory = nil
            return
        }

        let normalizedHistory = WorkspaceSessionHistorySnapshot(
            transcript: history.transcript?.isEmpty == true ? nil : history.transcript,
            normalScrollPosition: history.normalScrollPosition,
            wasAlternateBufferActive: history.wasAlternateBufferActive,
        )
        let hasRestorableContent = normalizedHistory.transcript != nil
            || normalizedHistory.normalScrollPosition != nil
            || normalizedHistory.wasAlternateBufferActive
        pendingRestoredHistory = hasRestorableContent ? normalizedHistory : nil
    }

    func setRestoredHistory(
        transcript: String?,
        normalScrollPosition: Double?,
        wasAlternateBufferActive: Bool,
    ) {
        setRestoredHistory(
            WorkspaceSessionHistorySnapshot(
                transcript: transcript,
                normalScrollPosition: normalScrollPosition,
                wasAlternateBufferActive: wasAlternateBufferActive,
            ),
        )
    }

    func consumeRestoredHistory() -> WorkspaceSessionHistorySnapshot? {
        let history = pendingRestoredHistory
        pendingRestoredHistory = nil
        return history
    }
}
