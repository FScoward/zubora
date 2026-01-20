import SwiftUI

@MainActor
@main
struct ZuboraApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some Scene {
        MenuBarExtra("Zubora", systemImage: "arrow.triangle.2.circlepath") {
            Button("Status: \(permissionStatus)") {
                permissionManager.requestPermissions()
            }
            .disabled(isPermissionGranted)
            
            Divider()
            
            Picker("Mode", selection: $appState.swapMode) {
                ForEach(SwapMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            
            Menu("Modifiers (Click)") {
                Toggle("Command (⌘)", isOn: Binding(
                    get: { appState.modifierFlags.contains(.command) },
                    set: { _ in appState.toggleModifier(.command) }
                ))
                Toggle("Option (⌥)", isOn: Binding(
                    get: { appState.modifierFlags.contains(.option) },
                    set: { _ in appState.toggleModifier(.option) }
                ))
                Toggle("Control (⌃)", isOn: Binding(
                    get: { appState.modifierFlags.contains(.control) },
                    set: { _ in appState.toggleModifier(.control) }
                ))
                Toggle("Shift (⇧)", isOn: Binding(
                    get: { appState.modifierFlags.contains(.shift) },
                    set: { _ in appState.toggleModifier(.shift) }
                ))
            }
            
            Divider()
            
            Button("Zoom Target (80%)") {
                appState.zoomTargetWindow()
            }
            .disabled(!appState.isTargetRegistered)
            
            Divider()
            
            Button("Check for Updates...") {
                UpdateManager.shared.checkForUpdates()
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
    
    init() {
        print("Zubora Launched")
        NSApplication.shared.setActivationPolicy(.accessory)
        EventManager.shared.startMonitoring()
        _ = UpdateManager.shared
    }
    
    var isPermissionGranted: Bool {
        permissionManager.hasAccessibilityPermission && permissionManager.hasScreenRecordingPermission
    }
    
    var permissionStatus: String {
        if isPermissionGranted {
            return "Active"
        } else {
            var missing = [String]()
            if !permissionManager.hasAccessibilityPermission { missing.append("Accessibility") }
            if !permissionManager.hasScreenRecordingPermission { missing.append("Screen Recording") }
            return "Missing: \(missing.joined(separator: ", "))"
        }
    }
}
