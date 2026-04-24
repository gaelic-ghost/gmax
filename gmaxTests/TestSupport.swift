//
//  TestSupport.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

@testable import gmax
import Testing

@MainActor
enum TestSupport {
    static func makeWorkspace(title: String) -> Workspace {
        let pane = PaneLeaf()
        return Workspace(
            title: title,
            root: .leaf(pane),
        )
    }

    static func makeLaunchContextBuilder(defaultCurrentDirectory: String) -> TerminalLaunchContextBuilder {
        TerminalLaunchContextBuilder(
            shellExecutable: "/bin/zsh",
            shellArguments: ["-l"],
            baseEnvironment: ["TERM": "xterm-256color"],
            defaultCurrentDirectory: defaultCurrentDirectory,
        )
    }
}

extension PaneLeaf {
    var requiredTerminalSessionID: TerminalSessionID {
        guard let terminalSessionID else {
            preconditionFailure("Test fixture expected a terminal pane.")
        }

        return terminalSessionID
    }

    var sessionID: TerminalSessionID {
        requiredTerminalSessionID
    }
}
