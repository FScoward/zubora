import SwiftUI
@preconcurrency import ApplicationServices
import CoreGraphics

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasScreenRecordingPermission: Bool = false
    
    private init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }
    
    func requestPermissions() {
        requestAccessibilityPermission()
        requestScreenRecordingPermission()
    }
    
    private func checkAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        self.hasAccessibilityPermission = isTrusted
    }
    
    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func checkScreenRecordingPermission() {
        // CGPreflightScreenCaptureAccess is available on macOS 11.0+
        if #available(macOS 11.0, *) {
            let isTrusted = CGPreflightScreenCaptureAccess()
            self.hasScreenRecordingPermission = isTrusted
        } else {
            // Fallback for older OS
            self.hasScreenRecordingPermission = true
        }
    }
    
    func requestScreenRecordingPermission() {
        if #available(macOS 11.0, *) {
            CGRequestScreenCaptureAccess()
        }
    }
}
