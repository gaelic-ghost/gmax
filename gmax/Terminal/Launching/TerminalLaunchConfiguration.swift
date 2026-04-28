//
//  TerminalLaunchConfiguration.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation

struct TerminalLaunchConfiguration: Hashable, Codable {
    var executable: String
    var arguments: [String]
    var environment: [String]?
    var currentDirectory: String?

    nonisolated static var loginShell: TerminalLaunchConfiguration {
        TerminalLaunchConfiguration(
            executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            arguments: ["-l"],
            environment: nil,
            currentDirectory: nil,
        )
    }

    nonisolated func normalizingCurrentDirectory() -> TerminalLaunchConfiguration {
        var configuration = self
        configuration.currentDirectory = TerminalCurrentDirectory.normalizedPath(
            fromHostDirectory: currentDirectory,
        )
        return configuration
    }
}
