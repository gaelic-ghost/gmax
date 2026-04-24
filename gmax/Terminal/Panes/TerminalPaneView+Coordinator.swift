//
//  TerminalPaneView+Coordinator.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
import OSLog
import SwiftTerm

extension TerminalPaneView {
    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let controller: TerminalPaneController

        init(controller: TerminalPaneController) {
            self.controller = controller
        }

        func makeHostingView() -> TerminalPaneHostView {
            let terminalView = controller.terminalView(
                for: controller.session.relaunchGeneration,
                processDelegate: self,
            )
            controller.attach(terminalView: terminalView)
            let hostingView = TerminalPaneHostView(terminalView: terminalView)
            startProcessIfNeeded(in: terminalView)
            return hostingView
        }

        func update(hostingView: TerminalPaneHostView) {
            startProcessIfNeeded(in: hostingView.terminalView)
        }

        func dismantle(hostingView: TerminalPaneHostView) {
            controller.detach(terminalView: hostingView.terminalView)
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            let resolvedTitle = title.isEmpty ? "Shell" : title
            Task { @MainActor in
                await Task.yield()
                controller.session.title = resolvedTitle
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor in
                await Task.yield()
                controller.session.currentDirectory = directory
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let paneID = controller.paneID.rawValue.uuidString
            let sessionID = controller.session.id.rawValue.uuidString
            if let exitCode {
                Logger.pane.notice("A shell session ended in a pane terminal host. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public). Exit status: \(exitCode)")
            } else {
                Logger.pane.notice("A shell session ended in a pane terminal host without a reported exit status. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public)")
            }
            Task { @MainActor in
                await Task.yield()
                controller.session.state = .exited(exitCode)
            }
        }

        private func startProcessIfNeeded(in terminalView: LocalProcessTerminalView) {
            let generation = controller.session.relaunchGeneration
            guard controller.needsProcessStart(for: generation) else {
                return
            }

            let pendingViewportRestore = controller.restoreHistoryIfNeeded(into: terminalView)

            let launch = controller.session.launchConfiguration
            terminalView.startProcess(
                executable: launch.executable,
                args: launch.arguments,
                environment: launch.environment,
                currentDirectory: launch.currentDirectory,
            )
            let paneID = controller.paneID.rawValue.uuidString
            let sessionID = controller.session.id.rawValue.uuidString
            let resolvedCurrentDirectory = launch.currentDirectory ?? "(default shell directory)"
            Logger.pane.notice("Launching a shell process for a pane terminal host. Pane ID: \(paneID, privacy: .public). Session ID: \(sessionID, privacy: .public). Executable: \(launch.executable, privacy: .public). Current directory: \(resolvedCurrentDirectory, privacy: .public)")
            controller.markProcessStarted(for: generation)
            Task { @MainActor in
                await Task.yield()
                controller.session.state = .running
            }
            if let pendingViewportRestore {
                Task { @MainActor in
                    await Task.yield()
                    await Task.yield()
                    guard controller.session.relaunchGeneration == generation else {
                        return
                    }
                    guard !pendingViewportRestore.shouldSkipRestoreBecauseAlternateBufferWasActive else {
                        return
                    }
                    guard let scrollPosition = pendingViewportRestore.normalScrollPosition else {
                        return
                    }

                    terminalView.scroll(toPosition: scrollPosition)
                }
            }
        }
    }
}
