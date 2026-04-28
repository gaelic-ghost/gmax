//
//  TerminalLaunchContextBuilder.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import SwiftTerm

struct TerminalLaunchContextBuilder {
    let shellExecutable: String
    let shellArguments: [String]
    let baseEnvironment: [String: String]
    let defaultCurrentDirectory: String

    static func live(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default,
    ) -> TerminalLaunchContextBuilder {
        let shellExecutable = resolvedShellExecutable(processInfo: processInfo, fileManager: fileManager)
        let defaultCurrentDirectory = resolvedCurrentDirectory(processInfo: processInfo, fileManager: fileManager)
        let swiftTermEnvironment = parseEnvironmentEntries(
            Terminal.getEnvironmentVariables(termName: "xterm-256color"),
        )
        let shellHandoffEnvironment = shellHandoffEnvironment(
            baseEnvironment: processInfo.environment,
            fileManager: fileManager,
        )
        let shellIntegrationPlan = makeShellIntegrationPlan(
            shellExecutable: shellExecutable,
            baseEnvironment: processInfo.environment,
            fileManager: fileManager,
        )
        let baseEnvironment = processInfo.environment
            .merging(swiftTermEnvironment, uniquingKeysWith: { _, new in new })
            .merging(stableTerminalEnvironment(), uniquingKeysWith: { _, new in new })
            .merging(shellHandoffEnvironment, uniquingKeysWith: { _, new in new })
            .merging(shellIntegrationPlan.environment, uniquingKeysWith: { _, new in new })

        return TerminalLaunchContextBuilder(
            shellExecutable: shellExecutable,
            shellArguments: shellIntegrationPlan.arguments,
            baseEnvironment: baseEnvironment,
            defaultCurrentDirectory: defaultCurrentDirectory,
        )
    }

    static func makeShellIntegrationPlan(
        shellExecutable: String,
        baseEnvironment: [String: String],
        fileManager: FileManager,
    ) -> ShellIntegrationPlan {
        let shellName = ShellIntegrationSupport.shellName(for: shellExecutable)
        switch shellName {
            case "zsh":
                return ShellIntegrationPlan(
                    arguments: ["-l"],
                    environment: ZshShellIntegration.environmentOverlay(
                        shellExecutable: shellExecutable,
                        baseEnvironment: baseEnvironment,
                        fileManager: fileManager,
                    ),
                )
            case "bash":
                let environment = BashShellIntegration.environmentOverlay(
                    shellExecutable: shellExecutable,
                    baseEnvironment: baseEnvironment,
                    fileManager: fileManager,
                )
                return ShellIntegrationPlan(
                    arguments: BashShellIntegration.launchArguments(environment: environment) ?? ["-l"],
                    environment: environment,
                )
            case "fish":
                return ShellIntegrationPlan(
                    arguments: ["-l"],
                    environment: FishShellIntegration.environmentOverlay(
                        shellExecutable: shellExecutable,
                        baseEnvironment: baseEnvironment,
                        fileManager: fileManager,
                    ),
                )
            default:
                return ShellIntegrationPlan(arguments: ["-l"], environment: [:])
        }
    }

    private static func resolvedShellExecutable(
        processInfo: ProcessInfo,
        fileManager: FileManager,
    ) -> String {
        let configuredShell = processInfo.environment["SHELL"] ?? "/bin/zsh"
        return fileManager.isExecutableFile(atPath: configuredShell) ? configuredShell : "/bin/zsh"
    }

    private static func resolvedCurrentDirectory(
        processInfo: ProcessInfo,
        fileManager: FileManager,
    ) -> String {
        if let workingDirectory = processInfo.environment["PWD"],
           isDirectory(workingDirectory, fileManager: fileManager) {
            return workingDirectory
        }

        let homeDirectory = NSHomeDirectory()
        if isDirectory(homeDirectory, fileManager: fileManager) {
            return homeDirectory
        }

        return fileManager.homeDirectoryForCurrentUser.path
    }

    private static func parseEnvironmentEntries(_ entries: [String]) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in entries {
            guard let separatorIndex = entry.firstIndex(of: "=") else {
                continue
            }

            let key = String(entry[..<separatorIndex])
            let value = String(entry[entry.index(after: separatorIndex)...])
            environment[key] = value
        }
        return environment
    }

    private static func environmentEntries(_ environment: [String: String]) -> [String] {
        environment
            .map { key, value in "\(key)=\(value)" }
            .sorted()
    }

    private static func stableTerminalEnvironment() -> [String: String] {
        [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "gmax",
            "ITERM_SHELL_INTEGRATION_INSTALLED": "Yes",
        ]
    }

    private static func shellHandoffEnvironment(
        baseEnvironment: [String: String],
        fileManager: FileManager,
    ) -> [String: String] {
        ZshShellIntegration.handoffEnvironment(
            baseEnvironment: baseEnvironment,
            fileManager: fileManager,
        )
        .merging(
            BashShellIntegration.handoffEnvironment(
                baseEnvironment: baseEnvironment,
                fileManager: fileManager,
            ),
            uniquingKeysWith: { _, new in new },
        )
        .merging(
            FishShellIntegration.handoffEnvironment(
                baseEnvironment: baseEnvironment,
                fileManager: fileManager,
            ),
            uniquingKeysWith: { _, new in new },
        )
    }

    private static func isDirectory(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue
    }

    func makeLaunchConfiguration(
        currentDirectory: String? = nil,
        environmentOverrides: [String: String] = [:],
    ) -> TerminalLaunchConfiguration {
        let resolvedCurrentDirectory = TerminalCurrentDirectory.normalizedPath(
            fromHostDirectory: currentDirectory,
        ) ?? TerminalCurrentDirectory.normalizedPath(
            fromHostDirectory: defaultCurrentDirectory,
        )
        var environment = baseEnvironment.merging(environmentOverrides, uniquingKeysWith: { _, new in new })
        environment["PWD"] = resolvedCurrentDirectory

        return TerminalLaunchConfiguration(
            executable: shellExecutable,
            arguments: shellArguments,
            environment: Self.environmentEntries(environment),
            currentDirectory: resolvedCurrentDirectory,
        )
    }
}

struct ShellIntegrationPlan {
    let arguments: [String]
    let environment: [String: String]
}
