//
//  DetailPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct DetailPane: View {
	@ObservedObject var model: ShellModel

	var body: some View {
		if let workspace = model.selectedWorkspace,
		   let pane = model.focusedPane,
		   let session = model.sessions.session(for: pane.sessionID) {
			ActivePaneDetails(
				workspaceTitle: workspace.title,
				pane: pane,
				session: session,
				onSplitRight: { model.splitFocusedPane(.right) },
				onSplitDown: { model.splitFocusedPane(.down) },
				onClose: { model.closeFocusedPane() }
			)
		} else {
			ContentUnavailableView("No Active Pane", systemImage: "rectangle.on.rectangle")
		}
	}
}

private struct ActivePaneDetails: View {
	let workspaceTitle: String
	let pane: PaneLeaf
	@ObservedObject var session: TerminalSession
	let onSplitRight: () -> Void
	let onSplitDown: () -> Void
	let onClose: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Active Pane")
				.font(.title2.weight(.semibold))

			VStack(alignment: .leading, spacing: 10) {
				Text("Actions")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)

				HStack {
					Button("Split Right", action: onSplitRight)
					Button("Split Down", action: onSplitDown)
					Button("Close Pane", action: onClose)
				}
				.buttonStyle(.bordered)
			}

			Group {
				labelValue("Workspace", workspaceTitle)
				labelValue("Title", session.title)
				labelValue("State", stateText(session.state))
				labelValue("Current Directory", session.currentDirectory ?? "Unavailable")
				labelValue("Pane ID", pane.id.rawValue.uuidString)
				labelValue("Session ID", pane.sessionID.rawValue.uuidString)
			}

			Spacer()
		}
		.padding()
	}

	@ViewBuilder
	private func labelValue(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.system(.body, design: .monospaced))
				.textSelection(.enabled)
		}
	}

	private func stateText(_ state: TerminalSessionState) -> String {
		switch state {
			case .idle:
				return "Idle"
			case .running:
				return "Running"
			case .exited(let exitCode):
				if let exitCode {
					return "Exited (\(exitCode))"
				}
				return "Exited"
		}
	}
}

#Preview {
	DetailPane(model: ShellModel())
}
