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
    
    // Rotation chain state
    private var originalTargetElement: AXUIElement?  // The first target (A)
    private var originalTargetFrame: CGRect?         // A's original position
    private var swapChain: [(element: AXUIElement, originalFrame: CGRect)] = []  // Swap history
    
    private init() {}
    
    func registerTarget(window: AXUIElement) {
        self.targetElement = window
        self.isTargetRegistered = true
        self.lastSwappedOther = nil // Reset on new registration
        
        // Initialize rotation chain
        self.originalTargetElement = window
        self.swapChain = []
        
        // Get initial frame for highlight
        if let frame = AccessibilityService.shared.getWindowFrame(element: window) {
            self.targetWindowFrame = frame
            self.originalTargetFrame = frame  // Remember original target position
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
            
            // Check if this is a rotation scenario (we already have swap history)
            if !swapChain.isEmpty {
                print("Rotation: '\(targetTitle)' returns to original, '\(clickedTitle)' goes to target slot")
                performRotation(currentTarget: target, currentTargetFrame: targetFrame, 
                               newWindow: clickedElement, newWindowFrame: clickedFrame)
            } else {
                // First swap - regular swap behavior
                print("First swap: '\(targetTitle)' \(targetFrame) with '\(clickedTitle)' \(clickedFrame)")
                performSwap(target: target, targetFrame: targetFrame, other: clickedElement, otherFrame: clickedFrame)
                
                // Add original target (A) to swap chain with its original position
                if let origTarget = originalTargetElement, let origFrame = originalTargetFrame {
                    swapChain.append((element: origTarget, originalFrame: origFrame))
                }
                
                // Also add the swap partner (B) with its original position (clickedFrame)
                // B will become the new target after performSwap, and we need to remember where it came from
                swapChain.append((element: clickedElement, originalFrame: clickedFrame))
            }
            
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
    
    /// Perform rotation: new window goes to target position, current target returns to its original position,
    /// original target (A) goes to new window's original position
    private func performRotation(currentTarget: AXUIElement, currentTargetFrame: CGRect,
                                  newWindow: AXUIElement, newWindowFrame: CGRect) {
        print("DEBUG: performRotation started")
        
        stopFrameTracking()
        
        guard let origTargetElement = originalTargetElement,
              let origTargetFrame = originalTargetFrame else {
            print("ERROR: No original target info for rotation")
            startFrameTracking()
            return
        }
        
        // Find current target's original position from swapChain
        // Current target should be in the chain if it was previously swapped
        var currentTargetOriginalFrame: CGRect? = nil
        for (element, frame) in swapChain {
            if CFEqual(element, currentTarget) {
                currentTargetOriginalFrame = frame
                break
            }
        }
        
        // If current target is the original target, use originalTargetFrame
        if CFEqual(currentTarget, origTargetElement) {
            currentTargetOriginalFrame = origTargetFrame
        }
        
        // If we still don't have it, it means current target was swapped in as "other" 
        // and we stored its frame when it first swapped. Check lastSwappedOther logic.
        // Actually, when B swaps with A, B becomes targetElement. B's original position was otherFrame at that time.
        // We need to track this better. Let's use swapChain to store each window that entered the target slot.
        
        let swapMode = self.swapMode
        
        // Determine positions:
        // 1. newWindow -> originalTargetFrame (the holy target position)
        // 2. currentTarget -> its original position (before it became target)
        // 3. originalTarget (A) -> newWindowFrame (where newWindow currently is)
        
        let newWindowDestination = origTargetFrame  // Goes to target slot
        let originalTargetDestination = newWindowFrame  // A goes to where C was
        
        // For currentTarget (B), we need its original position
        // If we don't have it, fall back to swapping just currentTarget and newWindow
        let currentTargetDestination: CGRect
        if let origPos = currentTargetOriginalFrame {
            currentTargetDestination = origPos
        } else {
            // Fallback: B goes to where the new window was (simple swap)
            print("WARNING: Could not find original position for current target, using newWindowFrame")
            currentTargetDestination = newWindowFrame
        }
        
        print("DEBUG: Rotation plan:")
        print("  - New window (\(AccessibilityService.shared.getTitle(element: newWindow))) -> \(newWindowDestination)")
        print("  - Current target (\(AccessibilityService.shared.getTitle(element: currentTarget))) -> \(currentTargetDestination)")
        print("  - Original target (\(AccessibilityService.shared.getTitle(element: origTargetElement))) -> \(originalTargetDestination)")
        
        // Perform the moves
        // Logic: Move windows in an order that minimizes overlap conflicts
        // 1. Move Original Target (A) to New Window's spot (posC) - clearing the way? No, covering C.
        // 2. Move Current Target (B) to its original spot (posB) - clearing target slot (posA).
        // 3. Move New Window (C) to Target slot (posA).
        
        print("DEBUG: Executing rotation moves...")
        
        // 1. Move A -> posC
        if swapMode == .swapAll {
            let res = AccessibilityService.shared.setWindowFrame(element: origTargetElement, frame: originalTargetDestination)
            print("  - Moved Original Target (A): \(res ? "Success" : "Failed")")
        } else {
            AccessibilityService.shared.setWindowPosition(element: origTargetElement, position: originalTargetDestination.origin)
            print("  - Moved Original Target (A) (Pos)")
        }
        
        // 2. Move B -> posB (Only if B != A)
        if !CFEqual(currentTarget, origTargetElement) {
            if swapMode == .swapAll {
                let res = AccessibilityService.shared.setWindowFrame(element: currentTarget, frame: currentTargetDestination)
                print("  - Moved Current Target (B): \(res ? "Success" : "Failed")")
            } else {
                AccessibilityService.shared.setWindowPosition(element: currentTarget, position: currentTargetDestination.origin)
                print("  - Moved Current Target (B) (Pos)")
            }
        }
        
        // 3. Move C -> posA
        if swapMode == .swapAll {
            let res = AccessibilityService.shared.setWindowFrame(element: newWindow, frame: newWindowDestination)
            print("  - Moved New Window (C): \(res ? "Success" : "Failed")")
        } else {
            AccessibilityService.shared.setWindowPosition(element: newWindow, position: newWindowDestination.origin)
            print("  - Moved New Window (C) (Pos)")
        }
        
        
        // Add NEW WINDOW (which becomes the new target) and its original position to swap chain
        // This ensures that in the next rotation, we know where to return this window to.
        swapChain.append((element: newWindow, originalFrame: newWindowFrame))
        
        // New window becomes the new target
        self.targetElement = newWindow
        
        print("DEBUG: Rotation complete.")
        print("  - New Target: \(AccessibilityService.shared.getTitle(element: newWindow))")
        print("  - Target Slot: \(newWindowDestination)")
        
        startFrameTracking()
        
        // Visual feedback
        SwapAnimationController.shared.showSwapFeedback(
            targetFrame1: newWindowDestination,
            targetFrame2: originalTargetDestination
        ) {
            print("DEBUG: Rotation visual feedback complete")
        }
    }
}
