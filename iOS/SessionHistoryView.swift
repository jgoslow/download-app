//
//  SessionHistoryView.swift
//  Basin (iOS)
//
//  List of past sessions. Tap to review. Re-send button for failed deliveries.
//
//  STATUS: Stub — iOS target not yet added to Xcode project.
//  See SETUP.md for Xcode configuration steps.
//

// import DownloadShared
// import SwiftUI
//
// struct SessionHistoryView: View {
//     @State private var sessions: [Session] = []
//
//     var body: some View {
//         List(sessions) { session in
//             SessionRow(session: session)
//         }
//         .navigationTitle("History")
//         .task {
//             sessions = (try? await SessionStore.live.loadAll()) ?? []
//         }
//     }
// }
//
// struct SessionRow: View {
//     let session: Session
//
//     var body: some View {
//         VStack(alignment: .leading, spacing: 4) {
//             HStack {
//                 Text(session.flowID.capitalized)
//                     .font(.headline)
//                 Spacer()
//                 Text(session.timestamp, style: .time)
//                     .font(.caption)
//                     .foregroundStyle(.secondary)
//             }
//             Text(session.rawText)
//                 .font(.body)
//                 .lineLimit(2)
//                 .foregroundStyle(.secondary)
//         }
//     }
// }
