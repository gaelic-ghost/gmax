//
//  TerminalAppearanceSettingsSection.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
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
                ForEach(TerminalTheme.allCases, id: \.rawValue) { theme in
                    Text(theme == .defaultTerminal ? "Default" : theme.rawValue.capitalized).tag(theme.rawValue)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("$ pwd")
                Text("~/Workspace/gmax")
                Text("$ swift build")
                Text("Build complete! Nerd glyphs: \u{e0b6} \u{f115} \u{f0e7}")
            }
            .font(Font(currentAppearance.resolvedFont))
            .foregroundStyle(Color(nsColor: currentAppearance.theme.foregroundColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: currentAppearance.theme.backgroundColor)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: currentAppearance.theme.cursorColor).opacity(0.35), lineWidth: 1),
            )
        }
    }
}
