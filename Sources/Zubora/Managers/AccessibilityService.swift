import ApplicationServices
import CoreGraphics
import Foundation
import AppKit

@MainActor
class AccessibilityService {
    static let shared = AccessibilityService()
    
    // MARK: - Core
    private let systemWideElement = AXUIElementCreateSystemWide()
    
    /// Activate a specific window and bring to front
    func activateWindow(_ element: AXUIElement) {
        // 1. Activate the application
        if let app = getApplication(for: element) {
            var pid: pid_t = 0
            if AXUIElementGetPid(app, &pid) == .success {
                if let nsApp = NSRunningApplication(processIdentifier: pid) {
                    nsApp.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
        
        // 2. Raise the window
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        
        // 3. Set Main
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        
        print("DEBUG: Activated Window Element with Title: \(getTitle(element: element))")
    }

    func getElementAtPosition(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
        
        if result == .success, let foundElement = element {
            print("AX Found element at \(point)")
            // Traverse up to find the window
            return getWindowElement(for: foundElement)
        } else {
            print("AX Failed to find any element at \(point). Error: \(result.rawValue)")
        }
        return nil
    }
    
    private func getWindowElement(for element: AXUIElement) -> AXUIElement? {
        // 1. Try direct Window Attribute
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXWindow" as CFString, &windowRef) == .success,
           let window = windowRef {
            return (window as! AXUIElement)
        }

        // 2. Try Top Level UI Element
        var topLevel: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXTopLevelUIElement" as CFString, &topLevel) == .success,
           let top = topLevel {
             return (top as! AXUIElement)
        }
        
        // 3. Fallback: Manual Traversal
        var currentElement = element
        
        // Loop to find the window role
        // Increased limit to 50 for deep hierarchies (e.g. Electron apps)
        for _ in 0..<50 {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role)
            
            if let roleStr = role as? String {
                if roleStr == kAXWindowRole as String {
                    return currentElement
                }
            }
            
            var parent: AnyObject?
            let err = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent)
            
            if err == .success, let parentElement = parent {
                currentElement = parentElement as! AXUIElement
            } else {
                break
            }
        }
        return nil
    }
    
    // MARK: - Window Manipulation
    
    func getWindowFrame(element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        
        guard let posVal = positionValue, let sizeVal = sizeValue else { return nil }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        
        return CGRect(origin: point, size: size)
    }
    
    @discardableResult
    func setWindowFrame(element: AXUIElement, frame: CGRect) -> Bool {
        guard let originalFrame = getWindowFrame(element: element) else {
            return false
        }
        
        // Get the application and disable AXEnhancedUserInterface temporarily
        // (This is what Amethyst/Silica does for reliability)
        let app = getApplication(for: element)
        let hadEnhancedUI = disableEnhancedUserInterface(app: app)
        
        // Determine if we should set size (only if changed significantly)
        let threshold: CGFloat = 25.0
        let shouldSetSize = abs(originalFrame.size.width - frame.size.width) >= threshold ||
                            abs(originalFrame.size.height - frame.size.height) >= threshold
        
        // Silica pattern: Size → Position → Size (no delays!)
        if shouldSetSize {
            setSize(element, frame.size)
        }
        
        if originalFrame.origin != frame.origin {
            setPosition(element, frame.origin)
        }
        
        if shouldSetSize {
            setSize(element, frame.size)
        }
        
        // Restore AXEnhancedUserInterface
        if hadEnhancedUI {
            enableEnhancedUserInterface(app: app)
        }
        
        return true
    }
    
    // MARK: - Enhanced UI Interface Control
    
    private func getApplication(for element: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }
    
    private func disableEnhancedUserInterface(app: AXUIElement?) -> Bool {
        guard let app = app else { return false }
        
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value)
        
        if err == .success, let num = value as? NSNumber, num.boolValue {
            // Disable it
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            return true
        }
        return false
    }
    
    private func enableEnhancedUserInterface(app: AXUIElement?) {
        guard let app = app else { return }
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
    
    func setWindowPosition(element: AXUIElement, position: CGPoint) {
        setPosition(element, position)
    }
    
    private func setSize(_ element: AXUIElement, _ size: CGSize) {
        var sizeVal = size
        if let value = AXValueCreate(.cgSize, &sizeVal) {
             let err = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
             if err != .success { print("Failed to set Size: \(err.rawValue)") }
        }
    }
    
    private func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var pointVal = point
        if let value = AXValueCreate(.cgPoint, &pointVal) {
             let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
             if err != .success { print("Failed to set Position: \(err.rawValue)") }
        }
    }
    
    func getTitle(element: AXUIElement) -> String {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String ?? "Unknown"
    }
    
    func getWindowID(element: AXUIElement) -> CGWindowID? {
        // 1. Try Attribute
        if let id = getWindowIDFromAttribute(element) { return id }
        
        // 2. Fallback: Match PID and Frame
        guard let pid = getPID(element),
              let frame = getWindowFrame(element: element) else {
            return nil
        }
        
        return recoverWindowID(pid: pid, frame: frame)
    }
    
    private func getWindowIDFromAttribute(_ element: AXUIElement) -> CGWindowID? {
        var value: AnyObject?
        // Check for common variations
        let attributeNames = ["AXWindowNumber", "_AXWindowNumber", "AXWindowID"]
        
        for name in attributeNames {
             let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
             if err == .success, let number = value as? NSNumber {
                 return CGWindowID(number.intValue)
             }
        }
        return nil
    }
    
    private func getPID(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success {
            return pid
        }
        return nil
    }
    
    private func recoverWindowID(pid: pid_t, frame: CGRect) -> CGWindowID? {
        // Query CGWindowList for this PID
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        // Find match
        for info in windowInfos {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid else { continue }
            
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               let x = bounds["X"], let y = bounds["Y"],
               let w = bounds["Width"], let h = bounds["Height"] {
                
                // Match Frame with tolerance
                if abs(x - frame.origin.x) < 10 &&
                   abs(y - frame.origin.y) < 10 &&
                   abs(w - frame.width) < 10 &&
                   abs(h - frame.height) < 10 {
                    
                    if let id = info[kCGWindowNumber as String] as? CGWindowID {
                        return id
                    }
                }
            }
        }
        
        print("DEBUG: Failed to find matching CGWindow for Frame: \(frame) PID: \(pid)")
        return nil
    }
    
    func getWindowLevel(element: AXUIElement) -> Int? {
        guard let windowID = getWindowID(element: element) else { return nil }
        
        let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        if let windowInfo = windowList?.first,
           let layer = windowInfo[kCGWindowLayer as String] as? Int {
            return layer
        }
        return nil
    }
    
    private func logSizeConstraints(_ element: AXUIElement) {
        // Check AXMinimumSize
        var minSizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXMinimumSize" as CFString, &minSizeValue) == .success,
           let val = minSizeValue {
            var minSize = CGSize.zero
            AXValueGetValue(val as! AXValue, .cgSize, &minSize)
            print("DEBUG: Window MinSize = \(minSize)")
        }
        
        // Check AXMaximumSize
        var maxSizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXMaximumSize" as CFString, &maxSizeValue) == .success,
           let val = maxSizeValue {
            var maxSize = CGSize.zero
            AXValueGetValue(val as! AXValue, .cgSize, &maxSize)
            print("DEBUG: Window MaxSize = \(maxSize)")
        }
    }
}
