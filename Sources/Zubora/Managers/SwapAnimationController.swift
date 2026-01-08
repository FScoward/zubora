import Cocoa
import CoreGraphics

@MainActor
class SwapAnimationController {
    static let shared = SwapAnimationController()
    
    private var animationWindow: NSPanel?
    
    func animateSwap(
        window1ID: CGWindowID,
        frame1: CGRect,
        window2ID: CGWindowID,
        frame2: CGRect,
        targetFrame1: CGRect,
        targetFrame2: CGRect,
        completion: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else {
            completion()
            return
        }
        
        // Capture Images
        guard let image1 = captureWindow(windowID: window1ID),
              let image2 = captureWindow(windowID: window2ID) else {
            print("Failed to capture windows")
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
        panel.level = .init(Int(CGWindowLevelKey.floatingWindow.rawValue) + 1) // Above normal windows
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        let contentView = NSView(frame: screen.frame)
        contentView.wantsLayer = true
        panel.contentView = contentView
        
        // Create Views for Images
        let view1 = createImageView(image: image1, frame: convertToNSFrame(frame: frame1, screenHeight: screen.frame.height))
        let view2 = createImageView(image: image2, frame: convertToNSFrame(frame: frame2, screenHeight: screen.frame.height))
        
        contentView.addSubview(view1)
        contentView.addSubview(view2)
        
        self.animationWindow = panel
        panel.orderFront(nil)
        
        // Animate
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            view1.animator().frame = convertToNSFrame(frame: targetFrame1, screenHeight: screen.frame.height)
            view2.animator().frame = convertToNSFrame(frame: targetFrame2, screenHeight: screen.frame.height)
        } completionHandler: {
            panel.orderOut(nil)
            self.animationWindow = nil
            completion()
        }
    }
    
    private func captureWindow(windowID: CGWindowID) -> CGImage? {
        let option: CGWindowListOption = .optionIncludingWindow
        let image = CGWindowListCreateImage(.null, option, windowID, .boundsIgnoreFraming)
        return image
    }
    
    private func createImageView(image: CGImage, frame: NSRect) -> NSImageView {
        let imageView = NSImageView(frame: frame)
        imageView.image = NSImage(cgImage: image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true 
        return imageView
    }
    
    private func convertToNSFrame(frame: CGRect, screenHeight: CGFloat) -> NSRect {
        // AX/CG coordinates: origin top-left.
        // NS coordinates: origin bottom-left.
        // frame.origin.y in NS = screenHeight - (frame.origin.y + frame.height)
        let newY = screenHeight - (frame.origin.y + frame.height)
        return NSRect(x: frame.origin.x, y: newY, width: frame.size.width, height: frame.size.height)
    }
}
