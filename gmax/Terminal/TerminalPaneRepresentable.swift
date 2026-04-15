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
		hostingView.updateAccessibility(
			snapshot: accessibilitySnapshot,
			onFocus: onFocus,
			onRestart: onRestart,
			onSplitRight: onSplitRight,
			onSplitDown: onSplitDown,
			onClose: onClose
		)
		return hostingView
	}

	func updateNSView(_ nsView: TerminalHostingContainerView, context: Context) {
		applyCurrentAppearance(to: nsView)
		context.coordinator.update(hostingView: nsView, isFocused: isFocused)
		nsView.updateAccessibility(
			snapshot: accessibilitySnapshot,
			onFocus: onFocus,
			onRestart: onRestart,
			onSplitRight: onSplitRight,
			onSplitDown: onSplitDown,
			onClose: onClose
		)
	}

	static func dismantleNSView(_ nsView: TerminalHostingContainerView, coordinator: Coordinator) {
		coordinator.dismantle(hostingView: nsView)
	}

	private func applyCurrentAppearance(to hostingView: TerminalHostingContainerView) {
		let appearance = TerminalAppearance.persisted(
			fontName: terminalFontName,
			fontSize: terminalFontSize,
			themeName: terminalThemeName
		)
		appearance.apply(to: hostingView.terminalView)
		hostingView.onEffectiveAppearanceChange = { [weak terminalView = hostingView.terminalView] _ in
			guard let terminalView else {
				return
			}

			appearance.apply(to: terminalView)
		}
	}

	private var accessibilitySnapshot: TerminalAccessibilitySnapshot {
		let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let label: String
		if trimmedTitle.isEmpty || trimmedTitle == "Shell" {
			label = "Shell terminal"
		} else {
			label = "\(trimmedTitle) terminal"
		}
		let state = switch session.state {
			case .idle: "Shell ready to launch"
			case .running: "Shell running"
			case .exited(let exitCode): exitCode.map { "Shell exited with status \($0)" } ?? "Shell exited"
		}

		var valueParts: [String] = []
		if isFocused {
			valueParts.append("Focused")
		}
		valueParts.append(state)
		if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
			valueParts.append("Directory \(currentDirectory)")
		}

		return TerminalAccessibilitySnapshot(
			label: label,
			value: valueParts.joined(separator: ". "),
			help: "This terminal lives inside a workspace pane. Use the available accessibility actions to focus the pane, restart the shell, split the pane, or close the pane."
		)
	}
}
