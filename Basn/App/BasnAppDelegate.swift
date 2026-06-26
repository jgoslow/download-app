import ComposableArchitecture
import BasnCore
import SwiftData
import SwiftUI

private let appLogger = BasnLog.app
private let cacheLogger = BasnLog.caches

class BasnAppDelegate: NSObject, NSApplicationDelegate {
	var invisibleWindow: InvisibleWindow?
	var settingsWindow: NSWindow?
	var welcomeWindow: NSWindow?
	var statusItem: NSStatusItem!
	private var launchedAtLogin = false

	@Dependency(\.soundEffects) var soundEffect
	@Dependency(\.recording) var recording
	@Shared(.basnSettings) var basnSettings: BasnSettings

	func applicationDidFinishLaunching(_: Notification) {
		DiagnosticsLogging.bootstrapIfNeeded()
		// Ensure Parakeet/FluidAudio caches live under Application Support, not ~/.cache
		configureLocalCaches()
		seedDefaultData()
		if isTesting {
			appLogger.debug("Running in testing mode")
			return
		}

		Task {
			await soundEffect.preloadSounds()
		}
		launchedAtLogin = wasLaunchedAtLogin()
		appLogger.info("Application did finish launching")
		appLogger.notice("launchedAtLogin = \(self.launchedAtLogin)")

		// Set activation policy first
		updateAppMode()

		// Add notification observer
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAppModeUpdate),
			name: .updateAppMode,
			object: nil
		)

		// Start long-running app effects (global hotkeys, permissions, etc.)
		startLifecycleTasksIfNeeded()

		// Then present main views
		presentMainView()

		guard shouldOpenForegroundUIOnLaunch else {
			appLogger.notice("Suppressing foreground windows for login launch")
			return
		}

		if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
			presentSettingsView()
		} else {
			presentWelcomeWindow()
		}
		NSApp.activate(ignoringOtherApps: true)
	}

	private var shouldOpenForegroundUIOnLaunch: Bool {
		!(launchedAtLogin && !basnSettings.showDockIcon)
	}

	private func wasLaunchedAtLogin() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else {
			return false
		}

		return event.eventID == AEEventID(kAEOpenApplication)
			&& event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEEventClass(keyAELaunchedAsLogInItem)
	}

	private func startLifecycleTasksIfNeeded() {
		Task { @MainActor in
			await BasnApp.appStore.send(.task).finish()
		}
	}

	/// Sets XDG_CACHE_HOME so FluidAudio stores models under our app's
	/// Application Support folder, keeping everything in one place.
    private func configureLocalCaches() {
        do {
            let cache = try URL.basnApplicationSupport.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            setenv("XDG_CACHE_HOME", cache.path, 1)
            cacheLogger.info("XDG_CACHE_HOME set to \(cache.path)")
        } catch {
            cacheLogger.error("Failed to configure local caches: \(error.localizedDescription)")
        }
    }

	func presentMainView() {
		guard invisibleWindow == nil else {
			return
		}
		let transcriptionStore = BasnApp.appStore.scope(state: \.transcription, action: \.transcription)
		let transcriptionView = TranscriptionView(store: transcriptionStore).padding().padding(.top).padding(.top)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		invisibleWindow = InvisibleWindow.fromView(transcriptionView)
		invisibleWindow?.makeKeyAndOrderFront(nil)
	}

	func presentSettingsView() {
		if let settingsWindow = settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let settingsView = AppView(store: BasnApp.appStore)
			.modelContainer(BasnApp.modelContainer)
		let settingsWindow = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 700, height: 700),
			styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		settingsWindow.titleVisibility = .visible
		settingsWindow.contentView = NSHostingView(rootView: settingsView)
		settingsWindow.isReleasedWhenClosed = false
		settingsWindow.center()
		settingsWindow.toolbarStyle = NSWindow.ToolbarStyle.unified
		settingsWindow.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.settingsWindow = settingsWindow
	}

	func presentWelcomeWindow() {
		if let existing = welcomeWindow {
			existing.makeKeyAndOrderFront(nil)
			return
		}
		let view = WelcomeView {
			self.welcomeWindow?.close()
			self.welcomeWindow = nil
			self.presentSettingsView()
			NSApp.activate(ignoringOtherApps: true)
		}
		let window = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 480, height: 520),
			styleMask: [.titled, .fullSizeContentView, .closable],
			backing: .buffered,
			defer: false
		)
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.contentView = NSHostingView(rootView: view)
		window.isReleasedWhenClosed = false
		window.center()
		window.makeKeyAndOrderFront(nil)
		welcomeWindow = window
	}

	@objc private func handleAppModeUpdate() {
		Task {
			await updateAppMode()
		}
	}

	@MainActor
	private func updateAppMode() {
		appLogger.debug("showDockIcon = \(self.basnSettings.showDockIcon)")
		if self.basnSettings.showDockIcon {
			NSApp.setActivationPolicy(.regular)
		} else {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		presentSettingsView()
		return true
	}

	func applicationWillTerminate(_: Notification) {
		Task {
			await recording.cleanup()
		}
	}

	/// Handle basin:// URL scheme callbacks (OAuth)
	func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls {
			guard url.scheme == "basin", url.host == "oauth" else { continue }
			Task {
				await OAuthClient.shared.handleCallback(url: url)
			}
		}

		// Bring the settings window to front after OAuth redirect. Activate first, then
		// immediately close any windows we don't own (the empty SwiftUI WindowGroup that
		// surfaces on activation). Do this before makeKeyAndOrderFront so the settings
		// window ends up on top.
		if urls.contains(where: { $0.scheme == "basin" }), let settingsWindow {
			NSApplication.shared.activate(ignoringOtherApps: true)
			for window in NSApplication.shared.windows where window !== settingsWindow && window !== invisibleWindow {
				window.orderOut(nil)
			}
			settingsWindow.makeKeyAndOrderFront(nil)
		}
	}

	/// Seeds default data on first launch: one "Open" flow, all tools (disconnected), all channels (disabled).
	private func seedDefaultData() {
		let context = ModelContext(BasnApp.modelContainer)

		do {
			let flowCount = try context.fetchCount(FetchDescriptor<FlowDefinition>())
			if flowCount == 0 {
				let openFlow = FlowDefinition(
					id: "open",
					name: "Open",
					intro: "No structure. No prompts. Press record, speak, press stop.",
					cadence: "on-demand",
					sortOrder: 0
				)
				context.insert(openFlow)

				let setupFlow = FlowDefinition(
					id: "setup",
					name: "Setup",
					intro: "A guided flow to get Basn ready for you.",
					cadence: "on-demand",
					sortOrder: -1,
					isTemplate: false
				)
				setupFlow.prompts = FlowDefinition.setupPrompts
				context.insert(setupFlow)

				appLogger.info("Seeded default Open and Setup flows")
			}

			// Upsert default tools so new tools added to allDefaults appear in existing installs.
			let existingTools = try context.fetch(FetchDescriptor<Tool>())
			let existingToolIDs = Set(existingTools.map(\.id))
			var inserted = 0
			for tool in Tool.allDefaults where !existingToolIDs.contains(tool.id) {
				context.insert(tool)
				inserted += 1
			}
			if inserted > 0 {
				appLogger.info("Seeded \(inserted) new default tool(s)")
			}

			// Workflows are created organically (onboarding, Castellum patterns) — no seeding here.

try context.save()
		} catch {
			appLogger.error("Failed to seed default data: \(error.localizedDescription)")
		}
	}
}
