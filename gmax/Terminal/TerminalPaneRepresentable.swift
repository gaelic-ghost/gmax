//
//  TerminalPaneRepresentable.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI
import SwiftTerm

struct TerminalPaneRepresentable: NSViewRepresentable {
	let controller: TerminalPaneController
	let isFocused: Bool
	let onFocus: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(controller: controller, onFocus: onFocus)
	}

	func makeNSView(context: Context) -> TerminalHostingContainerView {
		context.coordinator.makeHostingView()
	}

	func updateNSView(_ nsView: TerminalHostingContainerView, context: Context) {
		context.coordinator.update(hostingView: nsView, isFocused: isFocused)
	}

	static func dismantleNSView(_ nsView: TerminalHostingContainerView, coordinator: Coordinator) {
		coordinator.dismantle(hostingView: nsView)
	}

	@MainActor
	final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
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
			hostingView.terminalView.terminate()
		}

		private func startProcessIfNeeded(in terminalView: LocalProcessTerminalView) {
			guard !didStartProcess else {
				return
			}

			let launch = controller.session.launchConfiguration
			terminalView.startProcess(
				executable: launch.executable,
				args: launch.arguments,
				currentDirectory: launch.currentDirectory
			)
			didStartProcess = true
			Task { @MainActor in
				controller.session.state = .running
			}
		}

		func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

		func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
			let resolvedTitle = title.isEmpty ? "Shell" : title
			Task { @MainActor in
				controller.session.title = resolvedTitle
			}
		}

		func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
			Task { @MainActor in
				controller.session.currentDirectory = directory
			}
		}

		func processTerminated(source: TerminalView, exitCode: Int32?) {
			Task { @MainActor in
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

final class TerminalHostingContainerView: NSView {
	let terminalView: LocalProcessTerminalView

	init(terminalView: LocalProcessTerminalView) {
		self.terminalView = terminalView
		super.init(frame: .zero)
		setup()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func setup() {
		wantsLayer = true
		terminalView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(terminalView)

		NSLayoutConstraint.activate([
			terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
			terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
			terminalView.topAnchor.constraint(equalTo: topAnchor),
			terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
	}
}
