import Cocoa
import SwiftUI

@MainActor
class EventManager: ObservableObject {
    static let shared = EventManager()
    
    private var flagsChangedMonitor: Any?
    private var keyDownMonitor: Any?
    private var clickMonitor: Any?
    
    func startMonitoring() {
        print("Starting EventManager monitoring...")
        print("Accessibility Trusted: \(AXIsProcessTrusted())")
        
        // Local Monitor (when app is active)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.option) && event.keyCode == 1 {
                print("Option+S detected via LOCAL Monitor")
                self.handleRegisterShortcut()
                return nil // Swallow event? No, let it pass
            }
            return event
        }
        
        // Global Monitor (when app is background)
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // kVK_ANSI_S is 0x01 (1)
            // print("Key down: \(event.keyCode), modifiers: \(event.modifierFlags)")
            
            if event.modifierFlags.contains(.option) && event.keyCode == 1 {
                print("Option+S detected via GLOBAL Monitor")
                self.handleRegisterShortcut()
            }
        }
        
        // Cmd+Click Monitor
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.modifierFlags.contains(.command) {
                // Global monitor event locationInWindow is usually in screen coordinates but inverted Y sometimes
                // Let's check: Cocoa uses bottom-left origin. AX uses top-left.
                // We need to convert.
                self.handleGlobalClick(event)
            }
        }
    }
    
    private func handleRegisterShortcut() {
        print("Option+S detected")
        // We need cursor position to find the window under cursor? 
        // Or active window? "Current Active Window" was the requirement.
        // Actually, requirement said "Option+S registers current active window".
        // BUT, global shortcut might not fire if we are not active? "addGlobalMonitor" works in bg.
        // To get active window, we might use NSWorkspace or AX.
        
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
    
    private func handleGlobalClick(_ event: NSEvent) {
        // Global monitor event locationInWindow is usually in screen coordinates but inverted Y sometimes
        // Let's check: Cocoa uses bottom-left origin. AX uses top-left.
        // event.cgEvent?.location gives Global Display Coordinates (Top-Left origin), which matches AX.
        if let cgEvent = event.cgEvent {
            let axPoint = cgEvent.location
            print("Cmd+Click detected at \(axPoint) (CGEvent)")
            
            Task { @MainActor in
                AppState.shared.handleSwapRequest(at: axPoint)
            }
        } else {
             // Fallback usually shouldn't happen for mouse events
             print("Cmd+Click event missing CGEvent")
        }
    }
}
