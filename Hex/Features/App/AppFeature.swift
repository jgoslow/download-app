//
//  AppFeature.swift
//  Basn
//
//  Created by Kit Langton on 1/26/25.
//

import AppKit
import ComposableArchitecture
import Dependencies
import BasnCore
import SwiftUI

@Reducer
struct AppFeature {
  enum ActiveTab: Equatable {
    case home
    case history
    case settings
    case flows
    case workflows
    case tools
    case about
    // TODO: Audit whether Basin needs speech-to-text transforms or other speech post-processing tools.
    // Requires review of capabilities provided by competing STT apps before re-exposing.
  }

	@ObservableState
	struct State {
		var transcription: TranscriptionFeature.State = .init()
		var settings: SettingsFeature.State = .init()
		var history: HistoryFeature.State = .init()
		var castellum: CastellumFeature.State = .init()
		var activeTab: ActiveTab = .home
		@Shared(.basnSettings) var basnSettings: BasnSettings
		@Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState

    // Permission state
    var microphonePermission: PermissionStatus = .notDetermined
    var accessibilityPermission: PermissionStatus = .notDetermined
    var inputMonitoringPermission: PermissionStatus = .notDetermined
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case transcription(TranscriptionFeature.Action)
    case settings(SettingsFeature.Action)
    case history(HistoryFeature.Action)
    case castellum(CastellumFeature.Action)
    case setActiveTab(ActiveTab)
    case task

    // Permission actions
    case checkPermissions
    case permissionsUpdated(mic: PermissionStatus, acc: PermissionStatus, input: PermissionStatus)
    case appActivated
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case modelStatusEvaluated(Bool)
  }

  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.transcription) var transcription
  @Dependency(\.permissions) var permissions
  @Dependency(\.notifications) var notifications

  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.transcription, action: \.transcription) {
      TranscriptionFeature()
    }

    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }

    Scope(state: \.history, action: \.history) {
      HistoryFeature()
    }

    Scope(state: \.castellum, action: \.castellum) {
      CastellumFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        return syncNotificationSchedule()

      case .task:
        return .merge(
          ensureSelectedModelReadiness(),
          startPermissionMonitoring(),
          syncNotificationSchedule()
        )

      case .transcription(.modelMissing):
        BasnLog.app.notice("Model missing - activating app and switching to settings")
        state.activeTab = .settings
        state.settings.shouldFlashModelSection = true
        return .run { send in
          await MainActor.run {
            BasnLog.app.notice("Activating app for model missing")
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
          try? await Task.sleep(for: .seconds(2))
          await send(.settings(.set(\.shouldFlashModelSection, false)))
        }

      case let .transcription(.analysisReceived(analysis, captureID)):
        return .send(.castellum(.planExecution(analysis, captureID: captureID)))

      case .transcription:
        return .none

      case .castellum:
        return .none

      case .settings:
        return .none

      case .history(.navigateToSettings):
        state.activeTab = .settings
        return .none
      case .history:
        return .none

      case let .setActiveTab(tab):
        state.activeTab = tab
        return .none

      // Permission handling
      case .checkPermissions:
        return .run { send in
          async let mic = permissions.microphoneStatus()
          async let acc = permissions.accessibilityStatus()
          async let input = permissions.inputMonitoringStatus()
          await send(.permissionsUpdated(mic: mic, acc: acc, input: input))
        }

      case let .permissionsUpdated(mic, acc, input):
        state.microphonePermission = mic
        state.accessibilityPermission = acc
        state.inputMonitoringPermission = input
        return .none

      case .appActivated:
        return .send(.checkPermissions)

      case .requestMicrophone:
        return .run { send in
          _ = await permissions.requestMicrophone()
          await send(.checkPermissions)
        }

      case .requestAccessibility:
        return .run { send in
          await permissions.requestAccessibility()
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .requestInputMonitoring:
        return .run { send in
          _ = await permissions.requestInputMonitoring()
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .modelStatusEvaluated:
        return .none
      }
    }
  }

  private func ensureSelectedModelReadiness() -> Effect<Action> {
    .run { send in
      @Shared(.basnSettings) var basnSettings: BasnSettings
      @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
      let selectedModel = basnSettings.selectedModel
      guard !selectedModel.isEmpty else {
        await send(.modelStatusEvaluated(false))
        return
      }
      let isReady = await transcription.isModelDownloaded(selectedModel)
      $modelBootstrapState.withLock { state in
        state.modelIdentifier = selectedModel
        if state.modelDisplayName?.isEmpty ?? true {
          state.modelDisplayName = selectedModel
        }
        state.isModelReady = isReady
        if isReady {
          state.lastError = nil
          state.progress = 1
        } else {
          state.progress = 0
        }
      }
      await send(.modelStatusEvaluated(isReady))
    }
  }

  private func syncNotificationSchedule() -> Effect<Action> {
    .run { _ in
      @Shared(.basnSettings) var basnSettings: BasnSettings
      if basnSettings.basinSettings.notificationsEnabled {
        let granted = await notifications.requestPermission()
        if granted {
          await notifications.scheduleDaily()
        } else {
          $basnSettings.withLock { $0.basinSettings.notificationsEnabled = false }
        }
      } else {
        await notifications.cancelAll()
      }
    }
  }

  private func startPermissionMonitoring() -> Effect<Action> {
    .run { send in
      await send(.checkPermissions)
      for await activation in permissions.observeAppActivation() {
        if case .didBecomeActive = activation {
          await send(.appActivated)
        }
      }
    }
  }
}

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var columnVisibility = NavigationSplitViewVisibility.automatic

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(selection: $store.activeTab) {
        // Primary
        Button {
          store.send(.setActiveTab(.home))
        } label: {
          Label("Basin", systemImage: "drop.circle")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.home)

        Button {
          store.send(.setActiveTab(.history))
        } label: {
          Label("History", systemImage: "clock")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.history)

        Divider()

        // Configuration
        Button {
          store.send(.setActiveTab(.settings))
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.settings)

        Button {
          store.send(.setActiveTab(.flows))
        } label: {
          Label("Flows", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.flows)

        Button {
          store.send(.setActiveTab(.workflows))
        } label: {
          Label("Workflows", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.workflows)

        Button {
          store.send(.setActiveTab(.tools))
        } label: {
          Label("Tools", systemImage: "wrench.and.screwdriver")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.tools)

        Button {
          store.send(.setActiveTab(.about))
        } label: {
          Label("About", systemImage: "info.circle")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.about)
      }
    } detail: {
      switch store.state.activeTab {
      case .home:
        HomeView(store: store)
          .navigationTitle("Basin")
      case .history:
        HistoryView(store: store.scope(state: \.history, action: \.history))
          .navigationTitle("History")
      case .settings:
        SettingsView(
          store: store.scope(state: \.settings, action: \.settings),
          microphonePermission: store.microphonePermission,
          accessibilityPermission: store.accessibilityPermission,
          inputMonitoringPermission: store.inputMonitoringPermission
        )
        .navigationTitle("Settings")
      case .flows:
        FlowsView()
          .navigationTitle("Flows")
      case .workflows:
        WorkflowsView(store: store.scope(state: \.settings, action: \.settings))
          .navigationTitle("Workflows")
      case .tools:
        ToolsView(store: store.scope(state: \.settings, action: \.settings))
          .navigationTitle("Tools")
      case .about:
        AboutView(store: store.scope(state: \.settings, action: \.settings))
          .navigationTitle("About")
      }
    }
    .enableInjection()
  }
}
