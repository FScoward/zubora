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
    
    func setWindowFrame(element: AXUIElement, frame: CGRect) {
        // 4-step strategy: Size -> Position -> Size -> Position
        // Each attribute is set twice to handle OS adjustments
        let delay = 0.02
        
        setSize(element, frame.size)
        Thread.sleep(forTimeInterval: delay)
        
        setPosition(element, frame.origin)
        Thread.sleep(forTimeInterval: delay)
        
        setSize(element, frame.size)
        Thread.sleep(forTimeInterval: delay)
        
        setPosition(element, frame.origin) // Final - ensures exact position
        
        // Verify
        if let currentFrame = getWindowFrame(element: element) {
            let posDiff = CGPoint(x: frame.origin.x - currentFrame.origin.x, y: frame.origin.y - currentFrame.origin.y)
            let sizeDiff = CGSize(width: frame.size.width - currentFrame.size.width, height: frame.size.height - currentFrame.size.height)
            print("DEBUG: Diff - Pos: \(posDiff), Size: \(sizeDiff)")
        }
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
        // Wait, strictly no public API for this in simple AX.
        // Usually we use _AXUIElementGetWindow(element, &id) which is private/soft-linked?
        // Actually, kAXWindowNumber attribute might be available?
        // Let's try kAXWindowNumberAttribute (which is "AXWindowNumber" string).
        // But kAXWindowNumberAttribute is not always standard.
        // Actually it is kAXWindowNumber which creates _AXUIElementGetWindow call internally? No.
        // Standard way:
        // AXUIElementCopyAttributeValue(..., "AXWindowNumber", ...)
        
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value)
        if err == .success, let number = value as? NSNumber {
            return CGWindowID(number.intValue)
        }
        return nil
    }
}
