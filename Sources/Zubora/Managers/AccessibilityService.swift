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
        // Get current frame to determine size change direction
        guard let originalFrame = getWindowFrame(element: element) else {
            return false
        }
        
        // Determine if we're growing or shrinking
        let isGrowing = frame.size.width > originalFrame.size.width ||
                        frame.size.height > originalFrame.size.height
        
        // Delay for API to process (20ms - balance between speed and reliability)
        let delay: UInt32 = 20_000  // 20ms
        
        // First pass: set position and size
        if isGrowing {
            setPosition(element, frame.origin)
            usleep(delay)
            setSize(element, frame.size)
            usleep(delay)
        } else {
            setSize(element, frame.size)
            usleep(delay)
            setPosition(element, frame.origin)
            usleep(delay)
        }
        
        // Second pass: reinforce both
        setPosition(element, frame.origin)
        setSize(element, frame.size)
        usleep(delay)
        
        // Verify and retry if needed
        if let currentFrame = getWindowFrame(element: element) {
            let posDiff = abs(frame.origin.x - currentFrame.origin.x) +
                          abs(frame.origin.y - currentFrame.origin.y)
            let sizeDiff = abs(frame.size.width - currentFrame.size.width) +
                           abs(frame.size.height - currentFrame.size.height)
            
            // If off by more than 5 pixels, do final attempt
            if posDiff > 5 || sizeDiff > 5 {
                setSize(element, frame.size)
                usleep(delay)
                setPosition(element, frame.origin)
                usleep(delay)
                setSize(element, frame.size)
            }
        }
        
        return true
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
