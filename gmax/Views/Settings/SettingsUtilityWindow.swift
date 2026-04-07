//
//  SettingsUtilityWindow.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI

struct SettingsUtilityWindow: View {
	@AppStorage(TerminalAppearanceDefaults.fontNameKey)
	private var terminalFontName = "MonoidNF-Regular"

	@AppStorage(TerminalAppearanceDefaults.fontSizeKey)
	private var terminalFontSize = TerminalAppearanceDefaults.defaultFontSize

	@AppStorage(TerminalAppearanceDefaults.themeKey)
	private var terminalThemeName = TerminalTheme.defaultTerminal.rawValue

	private let availableFonts = TerminalAppearance.availableFontOptions()

	var body: some View {
		Form {
			Section("Terminal Font") {
				Picker("Font", selection: $terminalFontName) {
					ForEach(availableFonts) { font in
						Text(font.displayName).tag(font.id)
					}
				}

				VStack(alignment: .leading, spacing: 8) {
					HStack {
						Text("Size")
						Spacer()
						Text("\(Int(terminalFontSize.rounded())) pt")
							.foregroundStyle(.secondary)
					}

					Slider(value: $terminalFontSize, in: 10...28, step: 1)
				}
			}

			Section("Theme") {
				Picker("Theme", selection: $terminalThemeName) {
					ForEach(TerminalTheme.allCases) { theme in
						Text(theme.displayName).tag(theme.rawValue)
					}
				}

				TerminalAppearancePreview(appearance: currentAppearance)
			}
		}
		.formStyle(.grouped)
		.scenePadding()
		.frame(width: 420)
	}

	private var currentAppearance: TerminalAppearance {
		TerminalAppearance.persisted(
			fontName: terminalFontName,
			fontSize: terminalFontSize,
			themeName: terminalThemeName
		)
	}
}

private struct TerminalAppearancePreview: View {
	let appearance: TerminalAppearance

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("$ pwd")
			Text("~/Workspace/gmax")
			Text("$ swift build")
			Text("Build complete! Nerd glyphs: \u{e0b6} \u{f115} \u{f0e7}")
		}
		.font(Font(appearance.resolvedFont))
		.foregroundStyle(Color(nsColor: appearance.theme.foregroundColor))
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Color(nsColor: appearance.theme.backgroundColor))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color(nsColor: appearance.theme.cursorColor).opacity(0.35), lineWidth: 1)
		)
	}
}

#Preview {
	SettingsUtilityWindow()
}
