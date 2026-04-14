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
	@AppStorage(TerminalAppearanceDefaults.fontNameKey)
	private var terminalFontName = TerminalAppearance.fallback.fontName

	@AppStorage(TerminalAppearanceDefaults.fontSizeKey)
	private var terminalFontSize = TerminalAppearance.fallback.fontSize

	@AppStorage(TerminalAppearanceDefaults.themeKey)
	private var terminalThemeName = TerminalAppearance.fallback.theme.rawValue

	let controller: TerminalPaneController
	let isFocused: Bool
	let onFocus: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(controller: controller, onFocus: onFocus)
	}

	func makeNSView(context: Context) -> TerminalHostingContainerView {
		let hostingView = context.coordinator.makeHostingView()
		applyCurrentAppearance(to: hostingView)
		return hostingView
	}

	func updateNSView(_ nsView: TerminalHostingContainerView, context: Context) {
		applyCurrentAppearance(to: nsView)
		context.coordinator.update(hostingView: nsView, isFocused: isFocused)
	}

	static func dismantleNSView(_ nsView: TerminalHostingContainerView, coordinator: Coordinator) {
		coordinator.dismantle(hostingView: nsView)
	}

	private var currentAppearance: TerminalAppearance {
		TerminalAppearance.persisted(
			fontName: terminalFontName,
			fontSize: terminalFontSize,
			themeName: terminalThemeName
		)
	}

	private func applyCurrentAppearance(to hostingView: TerminalHostingContainerView) {
		let appearance = currentAppearance
		appearance.apply(to: hostingView.terminalView)
		hostingView.onEffectiveAppearanceChange = { [weak terminalView = hostingView.terminalView] _ in
			guard let terminalView else {
				return
			}

			appearance.apply(to: terminalView)
		}
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

final class TerminalHostingContainerView: NSView {
	let terminalView: LocalProcessTerminalView
	var onEffectiveAppearanceChange: ((NSAppearance) -> Void)?

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

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		onEffectiveAppearanceChange?(effectiveAppearance)
	}
}
