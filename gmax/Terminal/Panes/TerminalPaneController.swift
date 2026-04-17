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
		processDelegate: LocalProcessTerminalViewDelegate
	) -> LocalProcessTerminalView {
		if
			let terminalView = retainedTerminalView,
			retainedTerminalGeneration == generation
		{
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
		processDelegate: LocalProcessTerminalViewDelegate
	) {
		terminalView.processDelegate = processDelegate
	}
}
