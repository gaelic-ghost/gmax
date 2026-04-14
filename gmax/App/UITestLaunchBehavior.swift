//
//  UITestLaunchBehavior.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import Foundation

enum UITestLaunchBehavior {
	private static let resetStateEnvironmentKey = "GMAX_UI_TEST_RESET_STATE"

	static var isEnabled: Bool {
		ProcessInfo.processInfo.environment[resetStateEnvironmentKey] == "1"
	}

	static func applyIfNeeded() {
		guard isEnabled else {
			return
		}

		resetAppState()
	}

	private static func resetAppState() {
		resetUserDefaults()
		resetShellPersistenceStore()
	}

	private static func resetUserDefaults() {
		let defaults = UserDefaults.standard

		if let bundleIdentifier = Bundle.main.bundleIdentifier {
			defaults.removePersistentDomain(forName: bundleIdentifier)
		}

		defaults.synchronize()
	}

	private static func resetShellPersistenceStore() {
		let fileManager = FileManager.default
		let storeURL = ShellPersistenceController.storeURL()
		let cleanupURLs = [
			storeURL,
			storeURL.appendingPathExtension("shm"),
			storeURL.appendingPathExtension("wal")
		]

		for cleanupURL in cleanupURLs where fileManager.fileExists(atPath: cleanupURL.path) {
			try? fileManager.removeItem(at: cleanupURL)
		}
	}
}
