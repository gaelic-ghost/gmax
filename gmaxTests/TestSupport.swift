//
//  TestSupport.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import Testing
@testable import gmax

@MainActor
enum TestSupport {
	static func makeWorkspace(title: String) -> Workspace {
		let pane = PaneLeaf()
		return Workspace(
			title: title,
			root: .leaf(pane)
		)
	}

	static func makeLaunchContextBuilder(defaultCurrentDirectory: String) -> TerminalLaunchContextBuilder {
		TerminalLaunchContextBuilder(
			shellExecutable: "/bin/zsh",
			shellArguments: ["-l"],
			baseEnvironment: ["TERM": "xterm-256color"],
			defaultCurrentDirectory: defaultCurrentDirectory
		)
	}
}
