import Cocoa
import SwiftUI

@MainActor
class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownMonitor: Any?
    
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
        
        // Setup Event Tap for Clicks (to allow swallowing)
        setupEventTap()
    }
    
    private func setupEventTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let _ = refcon else { return Unmanaged.passUnretained(event) }
                // let manager = Unmanaged<EventManager>.fromOpaque(refcon).takeUnretainedValue() // Unused
                
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
    
    // EventManager is a singleton, deinit is never called.
    // Removing deinit to avoid strict concurrency errors accessing MainActor isolated properties.
    /*
    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
    */
    
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
