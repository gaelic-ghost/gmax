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

    private var pendingRestoredTranscript: String?

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
        pendingRestoredTranscript = nil
        relaunchGeneration += 1
    }

    func setRestoredTranscript(_ transcript: String?) {
        let normalizedTranscript = transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pendingRestoredTranscript = normalizedTranscript?.isEmpty == false ? transcript : nil
    }

    func consumeRestoredTranscript() -> String? {
        let transcript = pendingRestoredTranscript
        pendingRestoredTranscript = nil
        return transcript
    }
}
