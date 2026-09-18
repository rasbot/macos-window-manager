import AppKit
import DockCore

final class ZoneCanvasView: NSView {
    var zones: [NormalizedZone] = [] {
        didSet {
            selectedZoneIndex = selectedZoneIndex.flatMap { zones.indices.contains($0) ? $0 : nil }
            onZonesChange?(zones)
            needsDisplay = true
        }
    }

    var gap: Double = 8 {
        didSet { needsDisplay = true }
    }

    var previewAspectRatio: CGFloat = 16.0 / 9.0 {
        didSet { needsDisplay = true }
    }

    var selectedZoneIndex: Int? {
        didSet {
            onSelectionChange?(selectedZoneIndex)
            needsDisplay = true
        }
    }

    var onSelectionChange: ((Int?) -> Void)?
    var onZonesChange: (([NormalizedZone]) -> Void)?

    private struct ResizeEdges: OptionSet {
        let rawValue: Int

        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let bottom = ResizeEdges(rawValue: 1 << 2)
        static let top = ResizeEdges(rawValue: 1 << 3)
    }

    private enum Interaction {
        case moving(index: Int, startPoint: CGPoint, startZone: NormalizedZone)
        case resizing(index: Int, edges: ResizeEdges, startPoint: CGPoint, startZone: NormalizedZone)
    }

    private var interaction: Interaction?
    private let canvasInset: CGFloat = 18
    private let handleSize: CGFloat = 10
    private let edgeHitWidth: CGFloat = 10
    private let minimumZoneSize = 0.10

    override var acceptsFirstResponder: Bool { true }

    var overlappingZoneIDs: Set<Int> {
        ZoneLayout(id: "editor", name: "Editor", zones: zones, gap: gap).overlappingZoneIDs
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        let area = drawingArea
        guard area.width.isFinite,
              area.height.isFinite,
              area.minX.isFinite,
              area.minY.isFinite,
              area.width > 0,
              area.height > 0 else {
            return
        }
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: area, xRadius: 8, yRadius: 8).fill()
        drawGrid(in: area)

        let overlappingIDs = overlappingZoneIDs
        for (index, zone) in zones.enumerated() {
            draw(zone: zone, at: index, isOverlapping: overlappingIDs.contains(zone.id))
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        guard let index = zoneIndex(at: point) else {
            selectedZoneIndex = nil
            interaction = nil
            return
        }

        selectedZoneIndex = index
        let zone = zones[index]
        let edges = resizeEdges(at: point, for: zone)
        if edges.isEmpty {
            interaction = .moving(index: index, startPoint: point, startZone: zone)
        } else {
            interaction = .resizing(index: index, edges: edges, startPoint: point, startZone: zone)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction else { return }
        let point = convert(event.locationInWindow, from: nil)
        let area = drawingArea
        guard area.width > 0, area.height > 0 else { return }

        switch interaction {
        case let .moving(index, startPoint, startZone):
            guard zones.indices.contains(index) else { return }
            let deltaX = Double((point.x - startPoint.x) / area.width)
            let deltaY = Double((point.y - startPoint.y) / area.height)
            let x = snapped(clamp(startZone.x + deltaX, minimum: 0, maximum: 1 - startZone.width))
            let y = snapped(clamp(startZone.y + deltaY, minimum: 0, maximum: 1 - startZone.height))
            zones[index] = NormalizedZone(
                id: startZone.id,
                x: x,
                y: y,
                width: startZone.width,
                height: startZone.height
            )

        case let .resizing(index, edges, startPoint, startZone):
            guard zones.indices.contains(index) else { return }
            let deltaX = Double((point.x - startPoint.x) / area.width)
            let deltaY = Double((point.y - startPoint.y) / area.height)
            zones[index] = resizedZone(startZone, edges: edges, deltaX: deltaX, deltaY: deltaY)
        }
    }

    override func mouseUp(with event: NSEvent) {
        interaction = nil
    }

    private var drawingArea: CGRect {
        let availableArea = bounds.insetBy(dx: canvasInset, dy: canvasInset)
        guard availableArea.width > 0,
              availableArea.height > 0,
              previewAspectRatio.isFinite,
              previewAspectRatio > 0 else {
            return availableArea
        }

        let availableAspectRatio = availableArea.width / availableArea.height
        if availableAspectRatio > previewAspectRatio {
            let width = availableArea.height * previewAspectRatio
            return CGRect(
                x: availableArea.midX - width / 2,
                y: availableArea.minY,
                width: width,
                height: availableArea.height
            )
        }

        let height = availableArea.width / previewAspectRatio
        return CGRect(
            x: availableArea.minX,
            y: availableArea.midY - height / 2,
            width: availableArea.width,
            height: height
        )
    }

    private func frame(for zone: NormalizedZone) -> CGRect {
        let area = drawingArea
        return CGRect(
            x: area.minX + (area.width * CGFloat(zone.x)),
            y: area.minY + (area.height * CGFloat(zone.y)),
            width: area.width * CGFloat(zone.width),
            height: area.height * CGFloat(zone.height)
        )
    }

    private func visibleFrame(for zone: NormalizedZone) -> CGRect {
        let rawFrame = frame(for: zone)
        let requestedInset = CGFloat(max(0, gap / 2))
        let maximumInset = max(0, (min(rawFrame.width, rawFrame.height) - 2) / 2)
        return rawFrame.insetBy(dx: min(requestedInset, maximumInset), dy: min(requestedInset, maximumInset))
    }

    private func zoneIndex(at point: CGPoint) -> Int? {
        if let selectedZoneIndex,
           zones.indices.contains(selectedZoneIndex),
           frame(for: zones[selectedZoneIndex]).insetBy(dx: -edgeHitWidth, dy: -edgeHitWidth).contains(point) {
            return selectedZoneIndex
        }
        return zones.indices.reversed().first {
            frame(for: zones[$0]).insetBy(dx: -edgeHitWidth, dy: -edgeHitWidth).contains(point)
        }
    }

    private func resizeEdges(at point: CGPoint, for zone: NormalizedZone) -> ResizeEdges {
        let zoneFrame = frame(for: zone)
        guard zoneFrame.insetBy(dx: -edgeHitWidth, dy: -edgeHitWidth).contains(point) else { return [] }

        var edges: ResizeEdges = []
        if abs(point.x - zoneFrame.minX) <= edgeHitWidth { edges.insert(.left) }
        if abs(point.x - zoneFrame.maxX) <= edgeHitWidth { edges.insert(.right) }
        if abs(point.y - zoneFrame.minY) <= edgeHitWidth { edges.insert(.bottom) }
        if abs(point.y - zoneFrame.maxY) <= edgeHitWidth { edges.insert(.top) }
        return edges
    }

    private func resizedZone(
        _ zone: NormalizedZone,
        edges: ResizeEdges,
        deltaX: Double,
        deltaY: Double
    ) -> NormalizedZone {
        var left = zone.x
        var right = zone.x + zone.width
        var bottom = zone.y
        var top = zone.y + zone.height

        if edges.contains(.left) {
            left = snapped(clamp(zone.x + deltaX, minimum: 0, maximum: right - minimumZoneSize))
        }
        if edges.contains(.right) {
            right = snapped(clamp(zone.x + zone.width + deltaX, minimum: left + minimumZoneSize, maximum: 1))
        }
        if edges.contains(.bottom) {
            bottom = snapped(clamp(zone.y + deltaY, minimum: 0, maximum: top - minimumZoneSize))
        }
        if edges.contains(.top) {
            top = snapped(clamp(zone.y + zone.height + deltaY, minimum: bottom + minimumZoneSize, maximum: 1))
        }

        return NormalizedZone(
            id: zone.id,
            x: left,
            y: bottom,
            width: right - left,
            height: top - bottom
        )
    }

    private func draw(zone: NormalizedZone, at index: Int, isOverlapping: Bool) {
        let zoneFrame = visibleFrame(for: zone)
        let selected = index == selectedZoneIndex
        let color = isOverlapping ? NSColor.systemRed : NSColor.systemBlue
        let path = NSBezierPath(roundedRect: zoneFrame, xRadius: 8, yRadius: 8)

        color.withAlphaComponent(selected ? 0.50 : 0.26).setFill()
        path.fill()
        color.withAlphaComponent(selected ? 1 : 0.75).setStroke()
        path.lineWidth = selected ? 4 : 2
        path.stroke()

        let label = "\(index + 1)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(x: zoneFrame.midX - labelSize.width / 2, y: zoneFrame.midY - labelSize.height / 2),
            withAttributes: attributes
        )

        if selected {
            for handle in resizeHandles(for: zone) {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
                color.setStroke()
                let handlePath = NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2)
                handlePath.lineWidth = 1
                handlePath.stroke()
            }
        }
    }

    private func resizeHandles(for zone: NormalizedZone) -> [CGRect] {
        let zoneFrame = frame(for: zone)
        let half = handleSize / 2
        let points = [
            CGPoint(x: zoneFrame.minX, y: zoneFrame.minY),
            CGPoint(x: zoneFrame.midX, y: zoneFrame.minY),
            CGPoint(x: zoneFrame.maxX, y: zoneFrame.minY),
            CGPoint(x: zoneFrame.minX, y: zoneFrame.midY),
            CGPoint(x: zoneFrame.maxX, y: zoneFrame.midY),
            CGPoint(x: zoneFrame.minX, y: zoneFrame.maxY),
            CGPoint(x: zoneFrame.midX, y: zoneFrame.maxY),
            CGPoint(x: zoneFrame.maxX, y: zoneFrame.maxY)
        ]
        return points.map { CGRect(x: $0.x - half, y: $0.y - half, width: handleSize, height: handleSize) }
    }

    private func drawGrid(in area: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              area.width.isFinite,
              area.height.isFinite,
              area.width > 0,
              area.height > 0 else {
            return
        }

        context.saveGState()
        context.beginPath()
        for step in 1..<10 {
            let fraction = CGFloat(step) / 10
            context.move(to: CGPoint(x: area.minX + area.width * fraction, y: area.minY))
            context.addLine(to: CGPoint(x: area.minX + area.width * fraction, y: area.maxY))
            context.move(to: CGPoint(x: area.minX, y: area.minY + area.height * fraction))
            context.addLine(to: CGPoint(x: area.maxX, y: area.minY + area.height * fraction))
        }
        context.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }

    private func snapped(_ value: Double) -> Double {
        (value * 20).rounded() / 20
    }
}
