//
//  gmaxTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/6/26.
//

import CoreGraphics
import Testing
@testable import gmax

@MainActor
struct gmaxTests {
	@Test func renameWorkspaceUpdatesTheTitle() {
		let initialWorkspace = makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [initialWorkspace],
			selectedWorkspaceID: initialWorkspace.id
		)

		model.renameWorkspace(initialWorkspace.id, to: "Primary Shell")

		#expect(model.workspaces[0].title == "Primary Shell")
	}

	@Test func duplicateWorkspaceClonesTheLayoutAndSelectsTheCopy() {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let workspace = Workspace(
			title: "Workspace 1",
			root: .split(
				PaneSplit(
					axis: .horizontal,
					fraction: 0.4,
					first: .leaf(leftPane),
					second: .leaf(rightPane)
				)
			),
			focusedPaneID: rightPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id
		)

		model.duplicateWorkspace(workspace.id)

		#expect(model.workspaces.count == 2)
		#expect(model.selectedWorkspace?.id == model.workspaces[1].id)
		#expect(model.workspaces[1].title == "Workspace 1 Copy")

		let originalLeaves = Set(workspace.paneLeaves.map(\.id))
		let duplicatedWorkspace = model.workspaces[1]
		let duplicatedLeaves = Set(duplicatedWorkspace.paneLeaves.map(\.id))
		let duplicatedSessions = Set(duplicatedWorkspace.paneLeaves.map(\.sessionID))

		#expect(duplicatedWorkspace.paneCount == workspace.paneCount)
		#expect(originalLeaves.isDisjoint(with: duplicatedLeaves))
		#expect(Set(workspace.paneLeaves.map(\.sessionID)).isDisjoint(with: duplicatedSessions))
	}

	@Test func deleteWorkspaceRemovesItAndSelectsTheNeighbor() {
		let firstWorkspace = makeWorkspace(title: "Workspace 1")
		let secondWorkspace = makeWorkspace(title: "Workspace 2")
		let model = ShellModel(
			workspaces: [firstWorkspace, secondWorkspace],
			selectedWorkspaceID: firstWorkspace.id
		)

		model.deleteWorkspace(firstWorkspace.id)

		#expect(model.workspaces.count == 1)
		#expect(model.workspaces[0].id == secondWorkspace.id)
		#expect(model.selectedWorkspace?.id == secondWorkspace.id)
	}

	@Test func deleteWorkspaceDoesNothingWhenItIsTheLastWorkspace() {
		let workspace = makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id
		)

		model.deleteWorkspace(workspace.id)

		#expect(model.workspaces.count == 1)
		#expect(model.selectedWorkspace?.id == workspace.id)
	}

	private func makeWorkspace(title: String) -> Workspace {
		let pane = PaneLeaf()
		return Workspace(
			title: title,
			root: .leaf(pane),
			focusedPaneID: pane.id
		)
	}
}
