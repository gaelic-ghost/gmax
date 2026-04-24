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

enum TerminalShellPhase: Equatable {
    case unknown
    case atPrompt
    case runningCommand
}

enum ShellIntegrationEvent: Equatable {
    case promptStarted
    case commandStarted
    case commandFinished(exitStatus: Int32?)
}

enum TerminalHostEvent: Equatable {
    case shellIntegration(ShellIntegrationEvent)
    case notification(title: String, body: String)
}

struct TerminalAttentionNotification: Equatable {
    let title: String
    let body: String
    let receivedAt: Date
}

struct TerminalHostEventParser {
    private static let escape = UInt8(ascii: "\u{1B}")
    private static let osc = UInt8(ascii: "]")
    private static let bel = UInt8(ascii: "\u{07}")
    private static let stringTerminator = UInt8(ascii: "\\")

    private var bufferedBytes: [UInt8] = []

    mutating func ingest(_ bytes: ArraySlice<UInt8>) -> [TerminalHostEvent] {
        guard !bytes.isEmpty else {
            return []
        }

        bufferedBytes.append(contentsOf: bytes)
        var events: [TerminalHostEvent] = []

        while let event = nextEvent() {
            events.append(event)
        }

        return events
    }

    private mutating func nextEvent() -> TerminalHostEvent? {
        while true {
            guard !bufferedBytes.isEmpty else {
                return nil
            }

            if bufferedBytes[0] != Self.escape {
                bufferedBytes.removeFirst()
                continue
            }

            guard bufferedBytes.count >= 2 else {
                return nil
            }
            guard bufferedBytes[1] == Self.osc else {
                bufferedBytes.removeFirst()
                continue
            }
            guard let terminatorRange = oscTerminatorRange(in: bufferedBytes) else {
                return nil
            }

            let payload = Array(bufferedBytes[2..<terminatorRange.lowerBound])
            bufferedBytes.removeFirst(terminatorRange.upperBound)
            guard let payloadString = String(bytes: payload, encoding: .utf8) else {
                continue
            }

            if payloadString == "133;A" {
                return .shellIntegration(.promptStarted)
            }

            if payloadString.hasPrefix("133;C") {
                return .shellIntegration(.commandStarted)
            }

            if payloadString.hasPrefix("133;D") {
                let exitStatus = payloadString
                    .split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
                    .dropFirst(2)
                    .first
                    .flatMap { Int32($0) }
                return .shellIntegration(.commandFinished(exitStatus: exitStatus))
            }

            if payloadString.hasPrefix("777;notify;") {
                let notificationPayload = String(payloadString.dropFirst("777;".count))
                let parts = notificationPayload.split(
                    separator: ";",
                    maxSplits: 2,
                    omittingEmptySubsequences: false,
                )
                guard parts.count >= 3, parts[0] == "notify" else {
                    continue
                }

                return .notification(
                    title: String(parts[1]),
                    body: String(parts[2]),
                )
            }
        }
    }

    private func oscTerminatorRange(in bytes: [UInt8]) -> Range<Int>? {
        var index = 2
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Self.bel {
                return index..<(index + 1)
            }

            if byte == Self.escape {
                let nextIndex = index + 1
                if nextIndex >= bytes.count {
                    return nil
                }
                if bytes[nextIndex] == Self.stringTerminator {
                    return index..<(nextIndex + 1)
                }
            }

            index += 1
        }

        return nil
    }
}

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: TerminalSessionID
    let launchConfiguration: TerminalLaunchConfiguration

    @Published var title: String
    @Published var currentDirectory: String?
    @Published var state: TerminalSessionState
    @Published private(set) var shellPhase: TerminalShellPhase
    @Published private(set) var lastCommandExitStatus: Int32?
    @Published private(set) var hasActiveBell: Bool
    @Published private(set) var bellCount: Int
    @Published private(set) var lastBellAt: Date?
    @Published private(set) var lastAttentionNotification: TerminalAttentionNotification?
    @Published private(set) var relaunchGeneration: Int

    private var pendingRestoredHistory: WorkspaceSessionHistorySnapshot?

    init(
        id: TerminalSessionID,
        launchConfiguration: TerminalLaunchConfiguration = .loginShell,
        title: String = "Shell",
        currentDirectory: String? = nil,
        state: TerminalSessionState = .idle,
        shellPhase: TerminalShellPhase = .unknown,
        lastCommandExitStatus: Int32? = nil,
        hasActiveBell: Bool = false,
        bellCount: Int = 0,
        lastBellAt: Date? = nil,
        lastAttentionNotification: TerminalAttentionNotification? = nil,
        relaunchGeneration: Int = 0,
    ) {
        self.id = id
        self.launchConfiguration = launchConfiguration
        self.title = title
        self.currentDirectory = currentDirectory
        self.state = state
        self.shellPhase = shellPhase
        self.lastCommandExitStatus = lastCommandExitStatus
        self.hasActiveBell = hasActiveBell
        self.bellCount = bellCount
        self.lastBellAt = lastBellAt
        self.lastAttentionNotification = lastAttentionNotification
        self.relaunchGeneration = relaunchGeneration
    }

    func prepareForRelaunch() {
        title = "Shell"
        currentDirectory = launchConfiguration.currentDirectory
        state = .idle
        shellPhase = .unknown
        lastCommandExitStatus = nil
        hasActiveBell = false
        bellCount = 0
        lastBellAt = nil
        lastAttentionNotification = nil
        pendingRestoredHistory = nil
        relaunchGeneration += 1
    }

    func applyShellIntegrationEvent(_ event: ShellIntegrationEvent) {
        switch event {
            case .promptStarted:
                shellPhase = .atPrompt
            case .commandStarted:
                shellPhase = .runningCommand
                hasActiveBell = false
            case let .commandFinished(exitStatus):
                shellPhase = .atPrompt
                lastCommandExitStatus = exitStatus
        }
    }

    func clearShellIntegrationState() {
        shellPhase = .unknown
        lastCommandExitStatus = nil
    }

    func clearBellAttention() {
        hasActiveBell = false
    }

    func recordBell(at date: Date = Date()) {
        hasActiveBell = true
        bellCount += 1
        lastBellAt = date
    }

    func recordAttentionNotification(
        title: String,
        body: String,
        at date: Date = Date(),
    ) {
        lastAttentionNotification = TerminalAttentionNotification(
            title: title,
            body: body,
            receivedAt: date,
        )
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
