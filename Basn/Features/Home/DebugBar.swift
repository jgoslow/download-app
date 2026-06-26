//
//  DebugBar.swift
//  Basn — #if DEBUG only
//
//  Shown at the bottom of HomeView in debug builds. Provides a toggle for the
//  scenario recorder. Writing the flag here (via @AppStorage) goes to the correct
//  sandbox container UserDefaults — `defaults write` from Terminal does not.
//

import SwiftUI

#if DEBUG
struct DebugBar: View {
    @AppStorage("BasnRecordScenarios") private var recordScenarios = false

    var body: some View {
        HStack(spacing: 8) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange, in: Capsule())

            Toggle("Record scenarios", isOn: $recordScenarios)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(.secondary)

            if recordScenarios {
                Text("→ container/Documents/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.25), lineWidth: 1))
    }
}
#endif
