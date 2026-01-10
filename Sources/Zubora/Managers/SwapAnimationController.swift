import Cocoa
import CoreGraphics
import QuartzCore

@MainActor
class SwapAnimationController {
    static let shared = SwapAnimationController()
    
    private var animationWindow: NSPanel?
    private let animationDuration: CFTimeInterval = 0.2
    
    /// Lightweight animation - shows colored borders at target positions
    func showSwapFeedback(
        targetFrame1: CGRect,
        targetFrame2: CGRect,
        completion: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else {
            completion()
            return
        }
        
        // Create Panel
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .init(Int(CGWindowLevelKey.floatingWindow.rawValue) + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        let contentView = NSView(frame: screen.frame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear
        panel.contentView = contentView
        
        guard let rootLayer = contentView.layer else {
            completion()
            return
        }
        
        let screenHeight = screen.frame.height
        
        // Create border layers at target positions
        let border1 = createBorderLayer(
            frame: convertToNSFrame(frame: targetFrame1, screenHeight: screenHeight),
            color: NSColor.systemBlue
        )
        let border2 = createBorderLayer(
            frame: convertToNSFrame(frame: targetFrame2, screenHeight: screenHeight),
            color: NSColor.systemCyan
        )
        
        rootLayer.addSublayer(border1)
        rootLayer.addSublayer(border2)
        
        self.animationWindow = panel
        panel.orderFront(nil)
        
        // Animate: fade in quickly, then fade out
        CATransaction.begin()
        CATransaction.setAnimationDuration(animationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock {
            panel.orderOut(nil)
            self.animationWindow = nil
            completion()
        }
        
        // Fade out animation
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = animationDuration
        
        border1.add(fadeOut, forKey: "fadeOut")
        border2.add(fadeOut, forKey: "fadeOut")
        
        border1.opacity = 0
        border2.opacity = 0
        
        CATransaction.commit()
    }
    
    private func createBorderLayer(frame: NSRect, color: NSColor) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.backgroundColor = color.withAlphaComponent(0.15).cgColor
        layer.borderColor = color.cgColor
        layer.borderWidth = 3
        layer.cornerRadius = 8
        return layer
    }
    
    private func convertToNSFrame(frame: CGRect, screenHeight: CGFloat) -> NSRect {
        let newY = screenHeight - (frame.origin.y + frame.height)
        return NSRect(x: frame.origin.x, y: newY, width: frame.size.width, height: frame.size.height)
    }
}
