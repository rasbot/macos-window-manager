import AppKit

final class ZoneOverlayView: NSView {
    var zoneFrames: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    var highlightedIndex: Int? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, frame) in zoneFrames.enumerated() {
            let isHighlighted = index == highlightedIndex
            let path = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)

            let fillColor = isHighlighted
                ? NSColor.systemBlue.withAlphaComponent(0.62)
                : NSColor.systemBlue.withAlphaComponent(0.14)

            if isHighlighted {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.75)
                shadow.shadowBlurRadius = 18
                shadow.shadowOffset = .zero
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                fillColor.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                fillColor.setFill()
                path.fill()
            }

            (isHighlighted ? NSColor.white.withAlphaComponent(0.95) : NSColor.systemBlue.withAlphaComponent(0.55)).setStroke()
            path.lineWidth = isHighlighted ? 5 : 2
            path.stroke()

            drawLabel(for: index, in: frame, isHighlighted: isHighlighted)
        }
    }

    private func drawLabel(for index: Int, in frame: CGRect, isHighlighted: Bool) {
        let zoneLabel = "\(index + 1)" as NSString
        let zoneAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: isHighlighted ? 34 : 24,
                weight: isHighlighted ? .bold : .semibold
            ),
            .foregroundColor: NSColor.white
        ]
        let zoneSize = zoneLabel.size(withAttributes: zoneAttributes)
        let showsDropCue = isHighlighted && frame.width >= 150 && frame.height >= 90
        let zoneY = frame.midY - zoneSize.height / 2 + (showsDropCue ? 12 : 0)
        zoneLabel.draw(
            at: CGPoint(x: frame.midX - zoneSize.width / 2, y: zoneY),
            withAttributes: zoneAttributes
        )

        guard showsDropCue else { return }
        let cue = "RELEASE TO DOCK" as NSString
        let cueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
            .kern: 0.8
        ]
        let cueSize = cue.size(withAttributes: cueAttributes)
        cue.draw(
            at: CGPoint(x: frame.midX - cueSize.width / 2, y: zoneY - cueSize.height - 8),
            withAttributes: cueAttributes
        )
    }
}
