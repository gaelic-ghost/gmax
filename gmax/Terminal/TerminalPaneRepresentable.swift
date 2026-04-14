//
//  TerminalPaneRepresentable.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI

struct TerminalPaneRepresentable: NSViewRepresentable {
	@AppStorage(TerminalAppearanceDefaults.fontNameKey)
	private var terminalFontName = TerminalAppearance.fallback.fontName

	@AppStorage(TerminalAppearanceDefaults.fontSizeKey)
	private var terminalFontSize = TerminalAppearance.fallback.fontSize

	@AppStorage(TerminalAppearanceDefaults.themeKey)
	private var terminalThemeName = TerminalAppearance.fallback.theme.rawValue

	let controller: TerminalPaneController
	let session: TerminalSession
	let isFocused: Bool
	let onFocus: () -> Void
	let onRestart: () -> Void
	let onSplitRight: () -> Void
	let onSplitDown: () -> Void
	let onClose: () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(controller: controller, onFocus: onFocus)
	}

	func makeNSView(context: Context) -> TerminalHostingContainerView {
		let hostingView = context.coordinator.makeHostingView()
		applyCurrentAppearance(to: hostingView)
		configureAccessibility(for: hostingView)
		return hostingView
	}

	func updateNSView(_ nsView: TerminalHostingContainerView, context: Context) {
		applyCurrentAppearance(to: nsView)
		context.coordinator.update(hostingView: nsView, isFocused: isFocused)
		configureAccessibility(for: nsView)
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

	private func configureAccessibility(for hostingView: TerminalHostingContainerView) {
		hostingView.updateAccessibility(
			snapshot: accessibilitySnapshot,
			onFocus: onFocus,
			onRestart: onRestart,
			onSplitRight: onSplitRight,
			onSplitDown: onSplitDown,
			onClose: onClose
		)
	}

	private var accessibilitySnapshot: TerminalAccessibilitySnapshot {
		let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let label: String
		if trimmedTitle.isEmpty || trimmedTitle == "Shell" {
			label = "Shell terminal"
		} else {
			label = "\(trimmedTitle) terminal"
		}

		var valueParts: [String] = []
		if isFocused {
			valueParts.append("Focused")
		}
		valueParts.append(stateAccessibilityValue)
		if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
			valueParts.append("Directory \(currentDirectory)")
		}

		return TerminalAccessibilitySnapshot(
			label: label,
			value: valueParts.joined(separator: ". "),
			help: "This terminal lives inside a workspace pane. Use the available accessibility actions to focus the pane, restart the shell, split the pane, or close the pane."
		)
	}

	private var stateAccessibilityValue: String {
		switch session.state {
			case .idle:
				return "Shell ready to launch"
			case .running:
				return "Shell running"
			case .exited(let exitCode):
				if let exitCode {
					return "Shell exited with status \(exitCode)"
				}
				return "Shell exited"
		}
	}
}
