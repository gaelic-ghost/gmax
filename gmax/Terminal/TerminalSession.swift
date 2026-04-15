//
//  TerminalSession.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import Combine
import Foundation
import SwiftTerm

struct TerminalLaunchConfiguration: Hashable, Codable {
	var executable: String
	var arguments: [String]
	var environment: [String]?
	var currentDirectory: String?

	nonisolated static var loginShell: TerminalLaunchConfiguration {
		TerminalLaunchConfiguration(
			executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
			arguments: ["-l"],
			environment: nil,
			currentDirectory: nil
		)
	}
}

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
		relaunchGeneration: Int = 0
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

@MainActor
final class TerminalSessionRegistry {
	private let defaultLaunchConfiguration: TerminalLaunchConfiguration
	private var sessionsByID: [TerminalSessionID: TerminalSession]

	init(
		workspaces: [Workspace],
		defaultLaunchConfiguration: TerminalLaunchConfiguration = .loginShell
	) {
		self.defaultLaunchConfiguration = defaultLaunchConfiguration
		self.sessionsByID = [:]
		for workspace in workspaces {
			for leaf in workspace.paneLeaves {
				sessionsByID[leaf.sessionID] = TerminalSession(
					id: leaf.sessionID,
					launchConfiguration: defaultLaunchConfiguration,
					currentDirectory: defaultLaunchConfiguration.currentDirectory
				)
			}
		}
	}

	func ensureSession(
		id: TerminalSessionID,
		launchConfiguration: TerminalLaunchConfiguration? = nil
	) -> TerminalSession {
		if let session = sessionsByID[id] {
			return session
		}

		let resolvedLaunchConfiguration = launchConfiguration ?? defaultLaunchConfiguration
		let session = TerminalSession(
			id: id,
			launchConfiguration: resolvedLaunchConfiguration,
			currentDirectory: resolvedLaunchConfiguration.currentDirectory
		)
		sessionsByID[id] = session
		return session
	}

	func session(for id: TerminalSessionID) -> TerminalSession? {
		sessionsByID[id]
	}

	func removeSessions(notIn retainedSessionIDs: Set<TerminalSessionID>) {
		sessionsByID = sessionsByID.filter { retainedSessionIDs.contains($0.key) }
	}
}

@MainActor
final class TerminalPaneControllerStore {
	private var controllersByPaneID: [PaneID: TerminalPaneController] = [:]

	func controller(for pane: PaneLeaf, session: TerminalSession) -> TerminalPaneController {
		if let controller = controllersByPaneID[pane.id] {
			return controller
		}

		let controller = TerminalPaneController(paneID: pane.id, session: session)
		controllersByPaneID[pane.id] = controller
		return controller
	}

	func removeControllers(notIn retainedPaneIDs: Set<PaneID>) {
		controllersByPaneID = controllersByPaneID.filter { retainedPaneIDs.contains($0.key) }
	}

	func existingController(for paneID: PaneID) -> TerminalPaneController? {
		controllersByPaneID[paneID]
	}
}

@MainActor
final class TerminalPaneController: ObservableObject {
	let paneID: PaneID
	let session: TerminalSession
	private weak var attachedTerminalView: LocalProcessTerminalView?
	private var retainedTerminalView: LocalProcessTerminalView?
	private var retainedTerminalGeneration: Int?

	init(paneID: PaneID, session: TerminalSession) {
		self.paneID = paneID
		self.session = session
	}

	func terminalView(
		for generation: Int,
		processDelegate: LocalProcessTerminalViewDelegate,
		clickTarget: AnyObject,
		clickAction: Selector
	) -> LocalProcessTerminalView {
		if
			let terminalView = retainedTerminalView,
			retainedTerminalGeneration == generation
		{
			configureTerminalView(
				terminalView,
				processDelegate: processDelegate,
				clickTarget: clickTarget,
				clickAction: clickAction
			)
			return terminalView
		}

		let terminalView = LocalProcessTerminalView(frame: .zero)
		retainedTerminalView = terminalView
		retainedTerminalGeneration = generation
		configureTerminalView(
			terminalView,
			processDelegate: processDelegate,
			clickTarget: clickTarget,
			clickAction: clickAction
		)
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

	func restoreTranscriptIfNeeded(into terminalView: LocalProcessTerminalView) {
		guard let transcript = session.consumeRestoredTranscript() else {
			return
		}

		let bytes = ArraySlice(Array(transcript.utf8))
		guard !bytes.isEmpty else {
			return
		}

		terminalView.feed(byteArray: bytes)
	}

	func captureTranscript() -> String? {
		guard let terminalView = retainedTerminalView else {
			return nil
		}

		let transcriptData = terminalView
			.getTerminal()
			.getBufferAsData(kind: .normal, encoding: .utf8)

		guard
			!transcriptData.isEmpty,
			let transcript = String(data: transcriptData, encoding: .utf8)
		else {
			return nil
		}

		let normalizedTranscript = transcript.trimmingCharacters(in: .newlines)
		return normalizedTranscript.isEmpty ? nil : transcript
	}

	private func configureTerminalView(
		_ terminalView: LocalProcessTerminalView,
		processDelegate: LocalProcessTerminalViewDelegate,
		clickTarget: AnyObject,
		clickAction: Selector
	) {
		terminalView.processDelegate = processDelegate
		let recognizerSelector = clickAction
		let hasMatchingRecognizer = terminalView.gestureRecognizers.contains { recognizer in
			guard let clickRecognizer = recognizer as? NSClickGestureRecognizer else {
				return false
			}
			return clickRecognizer.target === clickTarget && clickRecognizer.action == recognizerSelector
		}
		guard !hasMatchingRecognizer else {
			return
		}

		let clickRecognizer = NSClickGestureRecognizer(target: clickTarget, action: clickAction)
		clickRecognizer.delaysPrimaryMouseButtonEvents = false
		terminalView.addGestureRecognizer(clickRecognizer)
	}
}
