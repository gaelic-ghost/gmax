//
//  BrowserPaneControllerStore.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation

@MainActor
final class BrowserPaneControllerStore {
    private var controllersByPaneID: [PaneID: BrowserPaneController] = [:]

    func controller(for pane: PaneLeaf, session: BrowserSession) -> BrowserPaneController {
        if let controller = controllersByPaneID[pane.id] {
            return controller
        }

        let controller = BrowserPaneController(paneID: pane.id, session: session)
        controllersByPaneID[pane.id] = controller
        return controller
    }

    func removeControllers(notIn retainedPaneIDs: Set<PaneID>) {
        controllersByPaneID = controllersByPaneID.filter { retainedPaneIDs.contains($0.key) }
    }
}
