//
//  ShellIntegrationSupport.swift
//  gmax
//
//  Created by Gale Williams on 4/24/26.
//

import Foundation

enum ShellIntegrationSupport {
    nonisolated static func shellName(for shellExecutable: String) -> String {
        URL(fileURLWithPath: shellExecutable).lastPathComponent
    }

    nonisolated static func wrapperDirectoryURL(
        shellName: String,
        fileManager: FileManager,
        rootDirectory: URL?,
    ) throws -> URL {
        if let rootDirectory {
            return rootDirectory.appendingPathComponent(shellName, isDirectory: true)
        }

        let applicationSupportDirectory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("gmax", isDirectory: true)
            .appendingPathComponent("ShellIntegration", isDirectory: true)
        return applicationSupportDirectory.appendingPathComponent(shellName, isDirectory: true)
    }

    nonisolated static func write(
        _ content: String,
        to url: URL,
        fileManager: FileManager,
    ) throws {
        let data = Data(content.utf8)
        if fileManager.fileExists(atPath: url.path),
           let existingData = fileManager.contents(atPath: url.path),
           existingData == data {
            return
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func originalHomeDirectory(from baseEnvironment: [String: String]) -> String {
        baseEnvironment["HOME"] ?? NSHomeDirectory()
    }

    nonisolated static func originalXDGConfigHome(from baseEnvironment: [String: String]) -> String {
        baseEnvironment["XDG_CONFIG_HOME"] ?? "\(originalHomeDirectory(from: baseEnvironment))/.config"
    }
}
