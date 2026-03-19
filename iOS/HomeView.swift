//
//  HomeView.swift
//  Download (iOS)
//
//  Home screen: list of DownloadTypes with schedule context.
//  Tap a type to enter the ritual screen and begin recording.
//
//  STATUS: Stub — iOS target not yet added to Xcode project.
//  See SETUP.md for Xcode configuration steps.
//

// import ComposableArchitecture
// import DownloadShared
// import SwiftUI
//
// struct HomeView: View {
//     let types: [DownloadType]
//
//     var body: some View {
//         NavigationStack {
//             List(types) { type in
//                 NavigationLink(destination: RecordingView(downloadType: type)) {
//                     DownloadTypeRow(type: type)
//                 }
//             }
//             .navigationTitle("Download")
//         }
//     }
// }
//
// struct DownloadTypeRow: View {
//     let type: DownloadType
//
//     var body: some View {
//         HStack {
//             VStack(alignment: .leading) {
//                 Text(type.name)
//                     .font(.headline)
//                 Text(scheduleLabel)
//                     .font(.caption)
//                     .foregroundStyle(.secondary)
//             }
//             Spacer()
//             Image(systemName: "mic.circle")
//                 .foregroundStyle(.accent)
//         }
//     }
//
//     var scheduleLabel: String {
//         guard type.schedule.reminderEnabled,
//               let time = type.schedule.reminderTime else {
//             return "On demand"
//         }
//         let days = type.schedule.days.map { $0.rawValue.capitalized }.joined(separator: ", ")
//         return "\(days) at \(time)"
//     }
// }
