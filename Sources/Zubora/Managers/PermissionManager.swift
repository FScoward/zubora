import SwiftUI
@preconcurrency import ApplicationServices
import CoreGraphics

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasScreenRecordingPermission: Bool = false
    
    private var pollingTimer: Timer?
    
    private init() {
        checkPermissions()
        if !hasAccessibilityPermission {
            startPolling()
        }
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
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        self.hasAccessibilityPermission = isTrusted
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
    
    private func startPolling() {
        stopPolling()
        // Poll every 1 second
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.checkPermissions()
                
                // Stop polling if we got permission
                if self.hasAccessibilityPermission {
                    self.stopPolling()
                }
            }
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
