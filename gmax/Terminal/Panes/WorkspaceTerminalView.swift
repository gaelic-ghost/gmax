//
//  WorkspaceTerminalView.swift
//  gmax
//
//  Created by Gale Williams on 4/15/26.
//

import AppKit
import SwiftTerm

final class WorkspaceTerminalView: LocalProcessTerminalView {
	func alignFirstResponderToTerminal() {
		guard window?.firstResponder !== self else {
			return
		}

		window?.makeFirstResponder(self)
	}
}
