import Cocoa
import SwiftUI

@MainActor
class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownMonitor: Any?
    
    @Published var isSwitching = false
    @Published var switchableWindows: [WindowInfo] = []
    @Published var currentSwitchIndex = 0
    private var originalWindow: WindowInfo?
    
    func startMonitoring() {
        print("Starting EventManager monitoring...")
        print("Accessibility Trusted: \(AXIsProcessTrusted())")
        
        // Local Monitor (when app is active)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.option) && event.keyCode == 1 {
                print("Option+S detected via LOCAL Monitor")
                self.handleRegisterShortcut()
                return nil // Swallow event
            }
            return event
        }
        
        // Global Monitor for Key Down (shortcuts)
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.option) && event.keyCode == 1 {
                print("Option+S detected via GLOBAL Monitor")
                self.handleRegisterShortcut()
            }
        }
        
        // Setup Event Tap for Clicks (to allow swallowing) and Key events
        setupEventTap()
    }
    
    private func setupEventTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventManager>.fromOpaque(refcon).takeUnretainedValue()
                
                if type == .flagsChanged {
                    // Check if modifiers are released while switching
                    if manager.isSwitching {
                        let flags = event.flags
                        // Require both Option and Control to be held.
                        // If either is missing, we consider it a release/commit.
                        let hasModifiers = flags.contains(.maskAlternate) && flags.contains(.maskControl)
                        
                        if !hasModifiers {
                            print("Modifiers released. Committing swap.")
                            Task { @MainActor in
                                manager.commitSwap()
                            }
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    
                    // Option + Z (KeyCode 6)
                    if keyCode == 6 && event.flags.contains(.maskAlternate) {
                        print("Option+Z detected (Zoom Toggle)")
                        Task { @MainActor in
                            AppState.shared.zoomTargetWindow()
                        }
                        // Swallow event
                        return nil
                    }

                    // Tab: 48
                    // Check for Control + Option
                    if keyCode == 48 && event.flags.contains(.maskAlternate) && event.flags.contains(.maskControl) {
                        print("Ctrl+Option+Tab detected")
                        Task { @MainActor in
                            manager.handleSwitchRequest()
                        }
                        return nil // Swallow event
                    }
                }
                
                if type == .leftMouseDown {
                    // Get current flags from event
                    let flags = event.flags
                    let requiredFlags = AppState.shared.modifierFlags
                    
                    // Convert CGEventFlags to NSEvent.ModifierFlags for comparison
                    var eventNsFlags: NSEvent.ModifierFlags = []
                    if flags.contains(.maskCommand) { eventNsFlags.insert(.command) }
                    if flags.contains(.maskAlternate) { eventNsFlags.insert(.option) }
                    if flags.contains(.maskControl) { eventNsFlags.insert(.control) }
                    if flags.contains(.maskShift) { eventNsFlags.insert(.shift) }
                    
                    // Check strict equality of modifiers (ignoring non-modifier flags)
                    if eventNsFlags == requiredFlags {
                        print("EventTap: Modifier+Click detected, swallowing event")
                        // Handle the click asynchronously on main thread
                        let location = event.location
                        Task { @MainActor in
                            AppState.shared.handleSwapRequest(at: location)
                        }
                        
                        // Swallow the event!
                        return nil
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        ) else {
            print("Failed to create Event Tap. Accessibility permissions missing?")
            return
        }
        
        self.eventTap = tap
        
        // Create run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        self.runLoopSource = runLoopSource
        
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Event Tap installed successfully")
    }
    
    // ...
    
    // MARK: - Switching Logic

    @MainActor
    private func handleSwitchRequest() {
        if !isSwitching {
            // Start Switching
            isSwitching = true
            
            // 1. Populate switchable windows first
        switchableWindows = WindowDiscoveryService.shared.getVisibleWindows()
        
        print("DEBUG: --- Switchable Windows List ---")
        let myPID = NSRunningApplication.current.processIdentifier
        print("DEBUG: My PID: \(myPID)")
        for (i, win) in switchableWindows.enumerated() {
            print("[\(i)] Title: '\(win.title)' (ID: \(win.id)) PID: \(win.app.processIdentifier) \(win.app.processIdentifier == myPID ? "[SELF]" : "")")
        }
        print("DEBUG: -------------------------------")
        
        // 2. Identify Original Window (Currently Focused) working against the list
            originalWindow = nil
            
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
                var focusedWindow: AnyObject?
                
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
                     let focusedElement = focusedWindow as! AXUIElement
                     
                    // Try to match focusedElement to one of our known visible windows
                    // Strategy: ID Match -> Frame Match
                    
                    if let id = AccessibilityService.shared.getWindowID(element: focusedElement) {
                        originalWindow = switchableWindows.first { $0.id == id }
                    }
                    
                    if originalWindow == nil, let frame = AccessibilityService.shared.getWindowFrame(element: focusedElement) {
                        // Fuzzy frame match
                        originalWindow = switchableWindows.first { info in
                            abs(info.frame.origin.x - frame.origin.x) < 20 &&
                            abs(info.frame.origin.y - frame.origin.y) < 20 &&
                            abs(info.frame.width - frame.width) < 20 &&
                            abs(info.frame.height - frame.height) < 20
                        }
                    }
                }
            }
            
            if let orig = originalWindow {
                print("DEBUG: Original Window identified: \(orig.title) (ID: \(orig.id))")
            } else {
                print("DEBUG: Failed to identify Original Window in switchable list.")
            }
            
            // Find index of original window to start from
            if let startWindow = originalWindow {
                if let index = switchableWindows.firstIndex(where: { $0.id == startWindow.id }) {
                    currentSwitchIndex = index
                } else {
                    currentSwitchIndex = 0
                }
            } else {
               currentSwitchIndex = 0
            }
            
            // Cycle to next window (first press)
            currentSwitchIndex = (currentSwitchIndex + 1) % switchableWindows.count
            
            // Show Panel AFTER setting index - but use async to let SwiftUI process the @Published change
            DispatchQueue.main.async {
                WindowSwitcherPanel.shared.show()
            }
        } else {
            // Already switching - just cycle the index
            // Panel is already visible, but NSHostingView may not update automatically
            if !switchableWindows.isEmpty {
                currentSwitchIndex = (currentSwitchIndex + 1) % switchableWindows.count
                // Force SwiftUI to re-render since @Published may not propagate in nonactivatingPanel
                WindowSwitcherPanel.shared.refreshContent()
            }
        }
        
        // Update highlight and log (for all presses)
        if !switchableWindows.isEmpty {
            let targetWindow = switchableWindows[currentSwitchIndex]
            print("Selected window index: \(currentSwitchIndex) title: \(targetWindow.title)")
            
            // Show Highlight on the new selection
            SwapAnimationController.shared.updateSelectionHighlight(frame: targetWindow.frame)
        }
    }
    
    @MainActor
    private func commitSwap() {
        // ALWAYS hide panel and remove highlight
        WindowSwitcherPanel.shared.hide()
        SwapAnimationController.shared.removeSelectionHighlight()
        
        guard isSwitching else { return }
        isSwitching = false
        
        guard !switchableWindows.isEmpty else { return }
        
        let currentTarget = switchableWindows[currentSwitchIndex]
        
        // 1. Activate the selected window (This is the standard Alt-Tab behavior trigger)
        currentTarget.activate()
        
        // 2. If Target is Set (Option+S) -> Swap Target <-> Selected Window
        guard AppState.shared.isTargetRegistered, let _ = AppState.shared.targetElement else {
            print("No target registered. Just switching focus.")
            // Cleanup
            originalWindow = nil
            switchableWindows = []
            return
        }
        
        print("Committing swap between Target and Selected: \(currentTarget.title)")
        
        // Delegate swap logic to AppState (handles animations, rotation, etc.)
        AppState.shared.swapWithTarget(currentTarget.element)
        
        // Cleanup
        originalWindow = nil
        switchableWindows = []
    }
    
    // Removed legacy register logic for now or keep it if needed later
    private func handleRegisterShortcut() {
        print("Option+S detected")
        
        if let frontApp = NSWorkspace.shared.frontmostApplication {
             // Get the focused window of the front app
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            var focusedWindow: AnyObject?
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
            
            if let window = focusedWindow {
                Task { @MainActor in
                    AppState.shared.registerTarget(window: window as! AXUIElement)
                }
            }
        }
    }

}
