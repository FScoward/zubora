import SwiftUI
import Combine
import ApplicationServices

enum SwapMode: String, CaseIterable, Identifiable {
    case swapAll = "Mode A (Pos & Size)"
    case swapPos = "Mode B (Pos Only)"
    
    var id: String { self.rawValue }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var swapMode: SwapMode = .swapAll
    @Published var isTargetRegistered: Bool = false
    @Published var targetWindowFrame: CGRect?
    
    private var targetElement: AXUIElement?
    
    private init() {}
    
    func registerTarget(window: AXUIElement) {
        self.targetElement = window
        self.isTargetRegistered = true
        // Get initial frame for highlight
        if let frame = AccessibilityService.shared.getWindowFrame(element: window) {
            self.targetWindowFrame = frame
            print("Target registered: \(frame)")
        }
    }
    
    func handleSwapRequest(at point: CGPoint) {
        guard let target = targetElement, let targetFrame = AccessibilityService.shared.getWindowFrame(element: target) else {
            print("No target registered or target invalid")
            isTargetRegistered = false
            return
        }
        
        guard let clickedElement = AccessibilityService.shared.getElementAtPosition(point) else {
            print("No window found at click")
            return
        }
        
        // Ensure strictly not the same window (simple check)
        if CFEqual(target, clickedElement) {
            let targetTitle = AccessibilityService.shared.getTitle(element: target)
            let clickedTitle = AccessibilityService.shared.getTitle(element: clickedElement)
            print("Clicked same window, ignoring. Target: '\(targetTitle)', Clicked: '\(clickedTitle)'")
            return
        }
        
        if let clickedFrame = AccessibilityService.shared.getWindowFrame(element: clickedElement) {
            let targetTitle = AccessibilityService.shared.getTitle(element: target)
            let clickedTitle = AccessibilityService.shared.getTitle(element: clickedElement)
            print("Swapping target '\(targetTitle)' \(targetFrame) with clicked '\(clickedTitle)' \(clickedFrame)")
            performSwap(target: target, targetFrame: targetFrame, other: clickedElement, otherFrame: clickedFrame)
        }
    }
    
    private func performSwap(target: AXUIElement, targetFrame: CGRect, other: AXUIElement, otherFrame: CGRect) {
        print("DEBUG: performSwap started")
        let swapMode = self.swapMode
        
        // Calculate target frames
        var newTargetFrame = otherFrame
        var newOtherFrame = targetFrame
        
        if swapMode == .swapPos {
            // Check Mode B: Position only, keep original sizes
            newTargetFrame.size = targetFrame.size
            newTargetFrame.origin = otherFrame.origin
            
            newOtherFrame.size = otherFrame.size
            newOtherFrame.origin = targetFrame.origin
        }
        
        // Get Window IDs for animation
        let targetID = AccessibilityService.shared.getWindowID(element: target) ?? 0
        let otherID = AccessibilityService.shared.getWindowID(element: other) ?? 0
        
        // Animate
        if targetID != 0 && otherID != 0 {
             print("DEBUG: Calling animateSwap")
             SwapAnimationController.shared.animateSwap(
                window1ID: targetID,
                frame1: targetFrame,
                window2ID: otherID,
                frame2: otherFrame,
                targetFrame1: newTargetFrame,
                targetFrame2: newOtherFrame
             ) {
                print("DEBUG: animateSwap completion block")
             }
        }
        
        print("DEBUG: Setting frames...")
        // Move windows immediately (behind the proxy)
        if swapMode == .swapAll {
            print("DEBUG: Setting Target Frame to \(newTargetFrame)")
            AccessibilityService.shared.setWindowFrame(element: target, frame: newTargetFrame)
            print("DEBUG: Setting Other Frame to \(newOtherFrame)")
            AccessibilityService.shared.setWindowFrame(element: other, frame: newOtherFrame)
        } else {
            print("DEBUG: Setting Target Position to \(newTargetFrame.origin)")
            AccessibilityService.shared.setWindowPosition(element: target, position: newTargetFrame.origin)
            print("DEBUG: Setting Other Position to \(newOtherFrame.origin)")
            AccessibilityService.shared.setWindowPosition(element: other, position: newOtherFrame.origin)
        }
        print("DEBUG: Frames set.")
        
        // Update target frame for glow
        self.targetWindowFrame = newTargetFrame
    }
}
