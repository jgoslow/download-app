//
//  RecordingView.swift
//  Basin (iOS)
//
//  Recording screen: shows ritual text + guided prompts while recording.
//  Tap to start/stop. Shows transcript and routing status on completion.
//
//  STATUS: Stub — iOS target not yet added to Xcode project.
//  See SETUP.md for Xcode configuration steps.
//

// import ComposableArchitecture
// import BasinShared
// import SwiftUI
//
// struct RecordingView: View {
//     let flow: Flow
//     @State private var isRecording = false
//     @State private var transcript: String = ""
//
//     var body: some View {
//         VStack(spacing: 24) {
//             // Ritual text shown before recording
//             if !isRecording && transcript.isEmpty {
//                 Text(flow.name)
//                     .font(.largeTitle.bold())
//                 // Ritual / guided prompts would appear here from Flow definition
//             }
//
//             Spacer()
//
//             // Record button
//             Button(action: toggleRecording) {
//                 Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
//                     .font(.system(size: 80))
//                     .foregroundStyle(isRecording ? .red : .accent)
//                     .symbolEffect(.pulse, isActive: isRecording)
//             }
//             .buttonStyle(.plain)
//
//             Spacer()
//         }
//         .padding()
//         .navigationTitle(flow.name)
//         .navigationBarTitleDisplayMode(.inline)
//     }
//
//     private func toggleRecording() {
//         isRecording.toggle()
//     }
// }
