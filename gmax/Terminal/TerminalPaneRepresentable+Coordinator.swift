//
//  TerminalPaneRepresentable+Coordinator.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
import OSLog
import SwiftTerm

extension TerminalPaneRepresentable {
	@MainActor
	final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
		private let paneLogger = Logger.gmax(.pane)
		let controller: TerminalPaneController
		let onFocus: () -> Void
		private var didStartProcess = false

		init(controller: TerminalPaneController, onFocus: @escaping () -> Void) {
			self.controller = controller
			self.onFocus = onFocus
		}

		func makeHostingView() -> TerminalHostingContainerView {
			let terminalView = LocalProcessTerminalView(frame: .zero)
			terminalView.processDelegate = self
			controller.attach(terminalView: terminalView)
			let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTerminalClick(_:)))
			clickRecognizer.delaysPrimaryMouseButtonEvents = false
			terminalView.addGestureRecognizer(clickRecognizer)
			let hostingView = TerminalHostingContainerView(terminalView: terminalView)
			startProcessIfNeeded(in: terminalView)
			return hostingView
		}

		func update(hostingView: TerminalHostingContainerView, isFocused: Bool) {
			startProcessIfNeeded(in: hostingView.terminalView)
			if isFocused, hostingView.window?.firstResponder !== hostingView.terminalView {
				hostingView.window?.makeFirstResponder(hostingView.terminalView)
			}
		}

		func dismantle(hostingView: TerminalHostingContainerView) {
			controller.detach(terminalView: hostingView.terminalView)
			hostingView.terminalView.terminate()
		}

		private func startProcessIfNeeded(in terminalView: LocalProcessTerminalView) {
			guard !didStartProcess else {
				return
			}

			controller.restoreTranscriptIfNeeded(into: terminalView)

			let launch = controller.session.launchConfiguration
			terminalView.startProcess(
				executable: launch.executable,
				args: launch.arguments,
				environment: launch.environment,
				currentDirectory: launch.currentDirectory
			)
			let paneID = controller.paneID.rawValue.uuidString
			let sessionID = controller.session.id.rawValue.uuidString
			let resolvedCurrentDirectory = launch.currentDirectory ?? "(default shell directory)"
			paneLogger.notice("Launching a shell process for a pane terminal host. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public). Executable: \(launch.executable, privacy: .public). Current directory: \(resolvedCurrentDirectory, privacy: .public)")
			didStartProcess = true
			Task { @MainActor in
				await Task.yield()
				controller.session.state = .running
			}
		}

		func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

		func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
			let resolvedTitle = title.isEmpty ? "Shell" : title
			Task { @MainActor in
				await Task.yield()
				controller.session.title = resolvedTitle
			}
		}

		func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
			Task { @MainActor in
				await Task.yield()
				controller.session.currentDirectory = directory
			}
		}

		func processTerminated(source: TerminalView, exitCode: Int32?) {
			let paneID = controller.paneID.rawValue.uuidString
			let sessionID = controller.session.id.rawValue.uuidString
			if let exitCode {
				paneLogger.notice("A shell session ended in a pane terminal host. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public). Exit status: \(exitCode)")
			} else {
				paneLogger.notice("A shell session ended in a pane terminal host without a reported exit status. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public)")
			}
			Task { @MainActor in
				await Task.yield()
				controller.session.state = .exited(exitCode)
			}
		}

		@objc
		private func handleTerminalClick(_ recognizer: NSClickGestureRecognizer) {
			guard let terminalView = recognizer.view as? LocalProcessTerminalView else {
				return
			}

			onFocus()
			terminalView.window?.makeFirstResponder(terminalView)
		}
	}
}
