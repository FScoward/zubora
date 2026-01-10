import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
class AccessibilityService {
    static let shared = AccessibilityService()
    
    private let systemWideElement = AXUIElementCreateSystemWide()
    
    // MARK: - Window Discovery
    
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
            // print("Found via AXWindow attribute")
            return (window as! AXUIElement)
        }

        // 2. Try Top Level UI Element
        var topLevel: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXTopLevelUIElement" as CFString, &topLevel) == .success,
           let top = topLevel {
             // Verify it is a window
             // print("Found via AXTopLevelUIElement attribute")
             return (top as! AXUIElement)
        }
        
        // 3. Fallback: Manual Traversal
        var currentElement = element
        
        // Loop to find the window role
        // Increased limit to 50 for deep hierarchies (e.g. Electron apps)
        for i in 0..<50 {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role)
            
            if let roleStr = role as? String {
                // print("Ancestor [\(i)]: Role = \(roleStr)")
                if roleStr == kAXWindowRole as String {
                    return currentElement
                }
            }
            
            var parent: AnyObject?
            let err = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent)
            
            if err == .success, let parentElement = parent {
                currentElement = parentElement as! AXUIElement
            } else {
                // print("Ancestor [\(i)]: No Parent (Error: \(err.rawValue))")
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
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value)
        if err == .success, let number = value as? NSNumber {
            return CGWindowID(number.intValue)
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
