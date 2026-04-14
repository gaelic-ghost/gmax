//
//  TerminalAppearanceSettingsSection.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct TerminalAppearanceSettingsSection: View {
	@Binding var terminalFontName: String
	@Binding var terminalFontSize: Double
	@Binding var terminalThemeName: String

	let availableFonts: [TerminalFontOption]
	let currentAppearance: TerminalAppearance

	var body: some View {
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
}
