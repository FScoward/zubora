import Cocoa
import CoreGraphics
import QuartzCore

@MainActor
class SwapAnimationController {
    static let shared = SwapAnimationController()
    
    private var animationWindow: NSPanel?
    private let animationDuration: CFTimeInterval = 0.6 // Increased duration for better visibility
    
    /// Rich animation - shows glowing borders and sparkles at target positions
    func showSwapFeedback(
        targetFrame1: CGRect,
        targetFrame2: CGRect,
        completion: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else {
            completion()
            return
        }
        
        // Clean up any existing animation window to prevent overlap
        if let existingPanel = animationWindow {
            existingPanel.orderOut(nil)
            animationWindow = nil
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
        
        // Convert frames
        let nsFrame1 = convertToNSFrame(frame: targetFrame1, screenHeight: screenHeight)
        let nsFrame2 = convertToNSFrame(frame: targetFrame2, screenHeight: screenHeight)
        
        // Create GLOWING border layers
        let border1 = createBorderLayer(frame: nsFrame1, color: NSColor.systemBlue)
        let border2 = createBorderLayer(frame: nsFrame2, color: NSColor.systemCyan)
        
        rootLayer.addSublayer(border1)
        rootLayer.addSublayer(border2)
        
        // Create SPARKLE emitters
        let emitter1 = createSparkleEmitter(frame: nsFrame1, color: NSColor.systemBlue.cgColor)
        let emitter2 = createSparkleEmitter(frame: nsFrame2, color: NSColor.systemCyan.cgColor)
        
        rootLayer.addSublayer(emitter1)
        rootLayer.addSublayer(emitter2)
        
        self.animationWindow = panel
        panel.orderFront(nil)
        
        // Animate: Pop in, then fade out
        CATransaction.begin()
        CATransaction.setAnimationDuration(animationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock {
            panel.orderOut(nil)
            self.animationWindow = nil
            completion()
        }
        
        // 1. Fade Out (Opacity)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = animationDuration
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        
        // 2. Scale Pop (Transform) - Optional subtle pop effect
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.9, 1.05, 1.0]
        scaleAnim.keyTimes = [0, 0.4, 1.0]
        scaleAnim.duration = animationDuration
        
        border1.add(fadeOut, forKey: "fadeOut")
        border1.add(scaleAnim, forKey: "pop")
        
        border2.add(fadeOut, forKey: "fadeOut")
        border2.add(scaleAnim, forKey: "pop")
        
        // Emitters fade out too
        emitter1.add(fadeOut, forKey: "fadeOut")
        emitter2.add(fadeOut, forKey: "fadeOut")
        
        CATransaction.commit()
    }

    private let RainbowLayerName = "RainbowTargetLayer"

    // MARK: - Persistent Target Highlight
    
    private var targetHighlightWindow: NSPanel?
    private var rainbowLayer: CALayer?
    
    /// Get the window ID of the highlight window, used to exclude it from coverage checks
    var highlightWindowID: CGWindowID? {
        targetHighlightWindow.map { CGWindowID($0.windowNumber) }
    }
    
    func updateTargetHighlight(frame: CGRect, isCovered: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let nsFrame = convertToNSFrame(frame: frame, screenHeight: screenHeight)
        let bounds = NSRect(origin: .zero, size: nsFrame.size)
        
        // Ensure window exists
        let window: NSPanel
        if let existingWin = targetHighlightWindow {
            window = existingWin
        } else {
            let panel = NSPanel(
                contentRect: nsFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            
            let contentView = NSView(frame: nsFrame)
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = .clear
            panel.contentView = contentView
            
            self.targetHighlightWindow = panel
            window = panel
            panel.orderFront(nil)
        }
        
        // Update Window Frame
        if window.frame != nsFrame {
            window.setFrame(nsFrame, display: true)
        }
        
        // Dynamically adjust window level based on coverage
        if isCovered {
            // When target is covered, use normal level so highlight goes behind
            if window.level != .normal {
                window.level = .normal
            }
        } else {
            // When target is visible, use floating level to stay above it
            if window.level != .floating {
                window.level = .floating
                window.orderFront(nil)
            }
        }
        
        // Update Layer
        guard let rootLayer = window.contentView?.layer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        var foundRainbow: CALayer? = nil
        
        if let sublayers = rootLayer.sublayers {
             // Safe cleanup: Iterate reversed to remove items while looping
             for layer in sublayers.reversed() {
                 if layer.name == RainbowLayerName {
                     foundRainbow = layer
                 } else {
                     // Remove artifacts (blue borders, old sparkles, etc)
                     layer.removeFromSuperlayer()
                 }
             }
        }
        
        if let container = foundRainbow {
            // Update existing layer (Preserves Animation)
            container.frame = bounds
            
            // Update Mask Path
            if let mask = container.mask as? CAShapeLayer {
                let path = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
                mask.path = path
            }
            
            // Update Gradient Frame
            if let gradient = container.sublayers?.first as? CAGradientLayer {
                let dimension = max(bounds.width, bounds.height) * 2.0
                gradient.frame = CGRect(
                    x: (bounds.width - dimension) / 2,
                    y: (bounds.height - dimension) / 2,
                    width: dimension,
                    height: dimension
                )
            }
            self.rainbowLayer = container
        } else {
            // Create new layer
            let rainbow = createRainbowBorder(bounds: bounds)
            rainbow.name = RainbowLayerName
            rootLayer.addSublayer(rainbow)
            self.rainbowLayer = rainbow
        }
        
        // Force display update
        window.contentView?.needsDisplay = true
        
        CATransaction.commit()
    }
    
    func removeTargetHighlight() {
        if let window = targetHighlightWindow {
            window.orderOut(nil)
            targetHighlightWindow = nil
            rainbowLayer = nil
        }
    }

    // MARK: - Effect Helpers
    
    private func createRainbowBorder(bounds: NSRect) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        container.name = RainbowLayerName
        
        // Mask for the border
        let mask = CAShapeLayer()
        let path = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        mask.path = path
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor // Opaque for mask
        mask.lineWidth = 4
        container.mask = mask
        
        // Rotating Gradient
        // Make it large enough to cover the bounds when rotated
        let dimension = max(bounds.width, bounds.height) * 2.0
        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.colors = [
            NSColor.red.cgColor,
            NSColor.orange.cgColor,
            NSColor.yellow.cgColor,
            NSColor.green.cgColor,
            NSColor.cyan.cgColor,
            NSColor.blue.cgColor,
            NSColor.purple.cgColor,
            NSColor.red.cgColor
        ]
        // Center the gradient layer
        gradient.frame = CGRect(
            x: (bounds.width - dimension) / 2,
            y: (bounds.height - dimension) / 2,
            width: dimension,
            height: dimension
        )
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0) // Not strictly used for conic usually, but good practice
        
        // Rotate Animation
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 2 * Double.pi
        rotation.duration = 2.0 // Speed of color flow
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        gradient.add(rotation, forKey: "rainbowRotate")
        
        container.addSublayer(gradient)
        return container
    }

    private func createBorderLayer(frame: NSRect, color: NSColor) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = color.cgColor
        layer.borderWidth = 3
        layer.cornerRadius = 8
        
        // Glow Effect
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 15
        layer.shadowOffset = .zero
        
        return layer
    }
    

    
    /// Creates a "burst" sparkle emitter for swap feedback
    private func createSparkleEmitter(frame: NSRect, color: CGColor) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: frame.midX, y: frame.midY)
        emitter.emitterShape = .rectangle
        emitter.emitterSize = frame.size
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        
        let cell = CAEmitterCell()
        // Burst settings: high velocity, short life, moderate count
        cell.birthRate = 0 // We will use pulse or just set a static rate for the short duration of the panel
        // Actually for a short animation window, constant emission is fine.
        cell.birthRate = 200
        cell.lifetime = 0.6
        cell.lifetimeRange = 0.2
        cell.velocity = 120
        cell.velocityRange = 40
        cell.emissionRange = .pi * 2
        
        cell.scale = 0.2
        cell.scaleRange = 0.1
        cell.spin = 4
        cell.spinRange = 4
        
        cell.color = color
        cell.alphaSpeed = -1.5
        
        if let img = createSparkleImage() {
            cell.contents = img
        }
        
        emitter.emitterCells = [cell]
        return emitter
    }
    
    private func createSparkleImage() -> CGImage? {
        let size = CGSize(width: 16, height: 16)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let ctx = context else { return nil }
        
        // Diamond/Star shape for sparkles
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.move(to: CGPoint(x: size.width / 2, y: 0))
        ctx.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        ctx.addLine(to: CGPoint(x: 0, y: size.height / 2))
        ctx.closePath()
        ctx.fillPath()
        
        return ctx.makeImage()
    }
    private func convertToNSFrame(frame: CGRect, screenHeight: CGFloat) -> NSRect {
        let newY = screenHeight - (frame.origin.y + frame.height)
        return NSRect(x: frame.origin.x, y: newY, width: frame.size.width, height: frame.size.height)
    }
}
