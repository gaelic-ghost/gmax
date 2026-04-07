//
//  TerminalAppearance.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import Foundation
import SwiftTerm

enum TerminalAppearanceDefaults {
	static let systemMonospacedFontName = "__SYSTEM_MONOSPACED__"
	static let fontNameKey = "terminalAppearance.fontName"
	static let fontSizeKey = "terminalAppearance.fontSize"
	static let themeKey = "terminalAppearance.theme"
	static let defaultFontSize = 13.0
}

struct TerminalFontOption: Identifiable, Hashable {
	let id: String
	let displayName: String
}

enum TerminalTheme: String, CaseIterable, Identifiable {
	case defaultTerminal
	case midnight
	case paper
	case phosphor

	var id: String { rawValue }

	var displayName: String {
		switch self {
			case .defaultTerminal:
				return "Default"
			case .midnight:
				return "Midnight"
			case .paper:
				return "Paper"
			case .phosphor:
				return "Phosphor"
		}
	}

	var backgroundColor: NSColor {
		switch self {
			case .defaultTerminal:
				return NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
			case .midnight:
				return NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)
			case .paper:
				return NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.92, alpha: 1)
			case .phosphor:
				return NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.03, alpha: 1)
		}
	}

	var foregroundColor: NSColor {
		switch self {
			case .defaultTerminal:
				return NSColor(calibratedRed: 0.87, green: 0.89, blue: 0.94, alpha: 1)
			case .midnight:
				return NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.00, alpha: 1)
			case .paper:
				return NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.20, alpha: 1)
			case .phosphor:
				return NSColor(calibratedRed: 0.54, green: 0.96, blue: 0.62, alpha: 1)
		}
	}

	var cursorColor: NSColor {
		switch self {
			case .defaultTerminal:
				return NSColor(calibratedRed: 0.98, green: 0.98, blue: 1.00, alpha: 1)
			case .midnight:
				return NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.95, alpha: 1)
			case .paper:
				return NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.31, alpha: 1)
			case .phosphor:
				return NSColor(calibratedRed: 0.82, green: 1.00, blue: 0.72, alpha: 1)
		}
	}

	var cursorTextColor: NSColor {
		switch self {
			case .paper:
				return backgroundColor
			case .defaultTerminal, .midnight, .phosphor:
				return NSColor.black
		}
	}
}

struct TerminalAppearance: Hashable {
	var fontName: String
	var fontSize: Double
	var theme: TerminalTheme

	static let fallbackFont = NSFont.monospacedSystemFont(
		ofSize: TerminalAppearanceDefaults.defaultFontSize,
		weight: .regular
	)

	static let fallback = TerminalAppearance(
		fontName: TerminalAppearanceDefaults.systemMonospacedFontName,
		fontSize: TerminalAppearanceDefaults.defaultFontSize,
		theme: .defaultTerminal
	)

	static func availableFontOptions(fontManager: NSFontManager = .shared) -> [TerminalFontOption] {
		let fixedPitchFonts = Set(fontManager.availableFontNames(with: .fixedPitchFontMask) ?? [])
		let installedFonts = fontManager.availableFonts

		let options = installedFonts
			.filter { fixedPitchFonts.contains($0) }
			.compactMap { fontName -> TerminalFontOption? in
				guard let font = NSFont(name: fontName, size: 13) else {
					return nil
				}

				return TerminalFontOption(
					id: fontName,
					displayName: font.displayName ?? fontName
				)
			}
			.sorted { lhs, rhs in
				lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
			}

		return [
			TerminalFontOption(
				id: TerminalAppearanceDefaults.systemMonospacedFontName,
				displayName: "System Monospaced"
			)
		] + options
	}

	static func persisted(
		fontName: String,
		fontSize: Double,
		themeName: String
	) -> TerminalAppearance {
		TerminalAppearance(
			fontName: fontName,
			fontSize: max(10, min(fontSize, 28)),
			theme: TerminalTheme(rawValue: themeName) ?? .defaultTerminal
		)
	}

	var resolvedFont: NSFont {
		let resolvedSize = CGFloat(max(10, min(fontSize, 28)))
		if fontName == TerminalAppearanceDefaults.systemMonospacedFontName {
			return NSFont.monospacedSystemFont(ofSize: resolvedSize, weight: .regular)
		}

		return NSFont(name: fontName, size: resolvedSize)
			?? NSFont.monospacedSystemFont(ofSize: resolvedSize, weight: .regular)
	}

	func apply(to terminalView: TerminalView) {
		terminalView.font = resolvedFont
		terminalView.nativeBackgroundColor = theme.backgroundColor
		terminalView.nativeForegroundColor = theme.foregroundColor
		terminalView.caretColor = theme.cursorColor
		terminalView.caretTextColor = theme.cursorTextColor
	}
}
