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
        // Log min/max size constraints for debugging
        logSizeConstraints(element)
        
        // Get current frame to determine size change direction
        guard let originalFrame = getWindowFrame(element: element) else {
            print("[setWindowFrame] Failed to get original frame")
            return false
        }
        
        print("[setWindowFrame] Original: \(originalFrame)")
        print("[setWindowFrame] Target:   \(frame)")
        
        // Determine if we're growing or shrinking
        let isGrowingWidth = frame.size.width > originalFrame.size.width
        let isGrowingHeight = frame.size.height > originalFrame.size.height
        let isGrowing = isGrowingWidth || isGrowingHeight
        
        print("[setWindowFrame] Direction: \(isGrowing ? "GROWING" : "SHRINKING")")
        
        // Adaptive strategy with verification
        let maxRetries = 5
        let delayMicroseconds: UInt32 = 50_000  // 50ms
        
        for attempt in 1...maxRetries {
            if isGrowing {
                // Growing: Position first (to avoid screen edge clipping), then Size
                setPosition(element, frame.origin)
                usleep(delayMicroseconds)
                setSize(element, frame.size)
                usleep(delayMicroseconds)
                // Second pass: Size then Position for fine-tuning
                setSize(element, frame.size)
                usleep(delayMicroseconds)
                setPosition(element, frame.origin)
            } else {
                // Shrinking: Size first, then Position
                setSize(element, frame.size)
                usleep(delayMicroseconds)
                setPosition(element, frame.origin)
                usleep(delayMicroseconds)
                // Second pass for fine-tuning
                setPosition(element, frame.origin)
                usleep(delayMicroseconds)
                setSize(element, frame.size)
            }
            
            usleep(delayMicroseconds)
            
            // Verify result
            if let currentFrame = getWindowFrame(element: element) {
                let posDiffX = abs(frame.origin.x - currentFrame.origin.x)
                let posDiffY = abs(frame.origin.y - currentFrame.origin.y)
                let sizeDiffW = abs(frame.size.width - currentFrame.size.width)
                let sizeDiffH = abs(frame.size.height - currentFrame.size.height)
                let totalPosDiff = posDiffX + posDiffY
                let totalSizeDiff = sizeDiffW + sizeDiffH
                
                print("[setWindowFrame] Attempt \(attempt): posDiff=\(totalPosDiff), sizeDiff=\(totalSizeDiff)")
                
                // Tolerance of 5 pixels total for each
                if totalPosDiff < 5 && totalSizeDiff < 5 {
                    print("[setWindowFrame] ✓ Success on attempt \(attempt)")
                    return true
                }
                
                // If size is clamped by min/max constraints, accept it
                if attempt == maxRetries {
                    print("[setWindowFrame] Final result (may be constrained by window limits)")
                }
            }
        }
        
        // Final verification and logging
        if let finalFrame = getWindowFrame(element: element) {
            let posDiff = CGPoint(x: frame.origin.x - finalFrame.origin.x, 
                                  y: frame.origin.y - finalFrame.origin.y)
            let sizeDiff = CGSize(width: frame.size.width - finalFrame.size.width, 
                                  height: frame.size.height - finalFrame.size.height)
            print("[setWindowFrame] Final Diff - Pos: \(posDiff), Size: \(sizeDiff)")
        }
        
        return false
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
