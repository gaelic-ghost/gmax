//
//  WindowSceneInterop.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import AppKit
import SwiftUI

extension AppWindowRole {
	var identifier: NSUserInterfaceItemIdentifier {
		NSUserInterfaceItemIdentifier(rawValue)
	}
}

struct WindowRoleAccessor: NSViewRepresentable {
	let role: AppWindowRole

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: .zero)
		view.isHidden = true
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		DispatchQueue.main.async {
			nsView.window?.identifier = role.identifier
		}
	}
}

struct WindowCloseConfirmationAccessor: NSViewRepresentable {
	let requiresConfirmation: Bool
	@Binding var isBypassingConfirmation: Bool

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: .zero)
		view.isHidden = true
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		context.coordinator.parent = self
		DispatchQueue.main.async {
			guard let window = nsView.window else {
				return
			}
			if context.coordinator.window !== window {
				context.coordinator.window = window
				window.delegate = context.coordinator
			}
		}
	}

	final class Coordinator: NSObject, NSWindowDelegate {
		var parent: WindowCloseConfirmationAccessor
		weak var window: NSWindow?
		private var isPresentingConfirmation = false

		init(parent: WindowCloseConfirmationAccessor) {
			self.parent = parent
		}

		func windowShouldClose(_ sender: NSWindow) -> Bool {
			if parent.isBypassingConfirmation {
				parent.isBypassingConfirmation = false
				return true
			}

			guard parent.requiresConfirmation else {
				return true
			}

			guard !isPresentingConfirmation else {
				return false
			}

			isPresentingConfirmation = true

			let alert = NSAlert()
			alert.alertStyle = .warning
			alert.messageText = "Quit gmax?"
			alert.informativeText = "Closing the last open pane will quit gmax for this session window. Quit now, or cancel and keep the pane open."
			alert.addButton(withTitle: "Quit")
			alert.addButton(withTitle: "Cancel")
			alert.beginSheetModal(for: sender) { [weak self] response in
				guard let self else {
					return
				}
				self.isPresentingConfirmation = false
				guard response == .alertFirstButtonReturn else {
					return
				}
				self.parent.isBypassingConfirmation = true
				sender.performClose(nil)
			}
			return false
		}
	}
}

extension View {
	func windowRole(_ role: AppWindowRole) -> some View {
		background(WindowRoleAccessor(role: role))
	}

	func windowCloseConfirmation(
		requiresConfirmation: Bool,
		isBypassingConfirmation: Binding<Bool>
	) -> some View {
		background(
			WindowCloseConfirmationAccessor(
				requiresConfirmation: requiresConfirmation,
				isBypassingConfirmation: isBypassingConfirmation
			)
		)
	}
}
