//
//  TerminalPaneControllerStore.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation

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
