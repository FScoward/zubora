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
    private var lastSwappedOther: AXUIElement? // Remember the last swap partner
    private var frameUpdateTimer: Timer?
    
    private init() {}
    
    func registerTarget(window: AXUIElement) {
        self.targetElement = window
        self.isTargetRegistered = true
        self.lastSwappedOther = nil // Reset on new registration
        // Get initial frame for highlight
        if let frame = AccessibilityService.shared.getWindowFrame(element: window) {
            self.targetWindowFrame = frame
            print("Target registered: \(frame)")
        }
        startFrameTracking()
    }
    
    private func startFrameTracking() {
        stopFrameTracking()
        frameUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTargetFrame()
            }
        }
    }
    
    private func stopFrameTracking() {
        frameUpdateTimer?.invalidate()
        frameUpdateTimer = nil
    }
    
    private func updateTargetFrame() {
        guard let target = targetElement else { return }
        if let frame = AccessibilityService.shared.getWindowFrame(element: target) {
            if frame != targetWindowFrame {
                targetWindowFrame = frame
            }
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
        
        // Check if clicked the target window itself
        if CFEqual(target, clickedElement) {
            // If we have a previous swap partner, swap with them again
            if let lastOther = lastSwappedOther,
               let lastOtherFrame = AccessibilityService.shared.getWindowFrame(element: lastOther) {
                let targetTitle = AccessibilityService.shared.getTitle(element: target)
                let otherTitle = AccessibilityService.shared.getTitle(element: lastOther)
                print("Re-swapping target '\(targetTitle)' with previous partner '\(otherTitle)'")
                performSwap(target: target, targetFrame: targetFrame, other: lastOther, otherFrame: lastOtherFrame)
            } else {
                print("Clicked target window, but no previous swap partner available")
            }
            return
        }
        
        if let clickedFrame = AccessibilityService.shared.getWindowFrame(element: clickedElement) {
            let targetTitle = AccessibilityService.shared.getTitle(element: target)
            let clickedTitle = AccessibilityService.shared.getTitle(element: clickedElement)
            print("Swapping target '\(targetTitle)' \(targetFrame) with clicked '\(clickedTitle)' \(clickedFrame)")
            performSwap(target: target, targetFrame: targetFrame, other: clickedElement, otherFrame: clickedFrame)
            
            // Remember this as the last swap partner
            self.lastSwappedOther = clickedElement
        }
    }
    
    private func performSwap(target: AXUIElement, targetFrame: CGRect, other: AXUIElement, otherFrame: CGRect) {
        print("DEBUG: performSwap started")
        
        // Pause frame tracking during swap to prevent interference
        stopFrameTracking()
        
        let swapMode = self.swapMode
        
        // Calculate target frames
        var newTargetFrame: CGRect
        var newOtherFrame: CGRect
        
        if swapMode == .swapAll {
            // Mode A: Full swap - exchange position AND size completely
            newTargetFrame = otherFrame   // Target gets other's position and size
            newOtherFrame = targetFrame   // Other gets target's position and size
        } else {
            // Mode B: Position only, keep original sizes, center-based
            let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let otherCenter = CGPoint(x: otherFrame.midX, y: otherFrame.midY)
            
            // Move target's center to other's center position
            newTargetFrame = CGRect(
                x: otherCenter.x - targetFrame.size.width / 2,
                y: otherCenter.y - targetFrame.size.height / 2,
                width: targetFrame.size.width,
                height: targetFrame.size.height
            )
            
            // Move other's center to target's center position
            newOtherFrame = CGRect(
                x: targetCenter.x - otherFrame.size.width / 2,
                y: targetCenter.y - otherFrame.size.height / 2,
                width: otherFrame.size.width,
                height: otherFrame.size.height
            )
        }
        
        // Get Window IDs for animation
        let targetID = AccessibilityService.shared.getWindowID(element: target) ?? 0
        let otherID = AccessibilityService.shared.getWindowID(element: other) ?? 0
        
        // Closure to perform the actual window move
        let moveWindows = { [self] in
            print("DEBUG: Setting frames...")
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
            
            // The window that moved INTO the target position becomes the new target
            self.targetElement = other
            print("DEBUG: New target is now the window that moved into the slot")
            
            // Resume frame tracking
            self.startFrameTracking()
        }
        
        // Move windows first, then show visual feedback
        moveWindows()
        
        // Show lightweight visual feedback (border animation)
        SwapAnimationController.shared.showSwapFeedback(
            targetFrame1: newTargetFrame,
            targetFrame2: newOtherFrame
        ) {
            print("DEBUG: Visual feedback complete")
        }
    }
}
