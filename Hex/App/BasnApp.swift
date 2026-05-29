import ComposableArchitecture
import Inject
import Sparkle
import AppKit
import SwiftData
import SwiftUI

@main
struct BasnApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}

	static let modelContainer: ModelContainer = {
		let schema = Schema([
			CaptureRecord.self,
			CaptureAnalysis.self,
			FlowDefinition.self,
			Tool.self,
			Workflow.self,
		])
		let config = ModelConfiguration(isStoredInMemoryOnly: false)
		do {
			return try ModelContainer(for: schema, configurations: [config])
		} catch {
			fatalError("Failed to create ModelContainer: \(error)")
		}
	}()

	@NSApplicationDelegateAdaptor(BasnAppDelegate.self) var appDelegate
  
    var body: some Scene {
        MenuBarExtra {
            CheckForUpdatesView()

            // TODO: Add "Flow History" section showing the last 10 flows run.
            // Clicking a flow entry should quick-link to the history view filtered to that flow.

            Button("Settings...") {
                appDelegate.presentSettingsView()
            }.keyboardShortcut(",")
			
			Divider()
			
			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}.keyboardShortcut("q")
		} label: {
			let image: NSImage = {
				let ratio = $0.size.height / $0.size.width
				$0.size.height = 18
				$0.size.width = 18 / ratio
				return $0
			}(NSImage(named: "BasnIcon")!)
			Image(nsImage: image)
		}


		WindowGroup {}.defaultLaunchBehavior(.suppressed)
			.modelContainer(Self.modelContainer)
			.commands {
				CommandGroup(after: .appInfo) {
					CheckForUpdatesView()

					Button("Settings...") {
						appDelegate.presentSettingsView()
					}.keyboardShortcut(",")
				}

				CommandGroup(replacing: .help) {}
			}
	}
}
