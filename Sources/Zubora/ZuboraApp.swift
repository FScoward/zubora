import SwiftUI

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
