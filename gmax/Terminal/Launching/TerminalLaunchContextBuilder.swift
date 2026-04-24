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
        let baseEnvironment = processInfo.environment
            .merging(swiftTermEnvironment, uniquingKeysWith: { _, new in new })
            .merging(stableTerminalEnvironment(), uniquingKeysWith: { _, new in new })

        return TerminalLaunchContextBuilder(
            shellExecutable: shellExecutable,
            shellArguments: ["-l"],
            baseEnvironment: baseEnvironment,
            defaultCurrentDirectory: defaultCurrentDirectory,
        )
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
        let resolvedCurrentDirectory = currentDirectory ?? defaultCurrentDirectory
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
