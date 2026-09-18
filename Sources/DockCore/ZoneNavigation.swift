import CoreGraphics

/// A direction used to move a window from one zone to a neighbouring zone.
public enum ZoneDirection: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
}

/// Zone lookup shared by pointer docking and keyboard docking.
///
/// Every rectangle is an AppKit global frame with a bottom-left origin, so
/// `up` means increasing `y`.
public enum ZoneNavigator {
    /// The zone directly under a point.
    public static func index(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// The zone that best describes where a window already sits: the zone holding
    /// its center, else the zone it overlaps most, else the zone whose center is
    /// nearest. Used to decide where an arrow-key move starts from.
    public static func index(matching rect: CGRect, in frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }

        if let hit = index(containing: CGPoint(x: rect.midX, y: rect.midY), in: frames) {
            return hit
        }

        var largestOverlapIndex: Int?
        var largestOverlapArea: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            let intersection = frame.intersection(rect)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > largestOverlapArea {
                largestOverlapArea = area
                largestOverlapIndex = index
            }
        }
        if let largestOverlapIndex {
            return largestOverlapIndex
        }

        return frames.indices.min {
            squaredCenterDistance(rect, frames[$0]) < squaredCenterDistance(rect, frames[$1])
        }
    }

    /// The neighbouring zone in a direction, or `nil` at the edge of the layout.
    ///
    /// Candidates are ranked by distance along the travel axis first so the move
    /// lands in the adjacent zone rather than skipping across the display, then by
    /// offset across that axis to break ties predictably.
    public static func index(from currentIndex: Int, direction: ZoneDirection, in frames: [CGRect]) -> Int? {
        guard frames.indices.contains(currentIndex) else { return nil }

        let origin = frames[currentIndex]
        var best: (index: Int, along: CGFloat, across: CGFloat)?

        for (index, frame) in frames.enumerated() where index != currentIndex {
            guard let offsets = travelOffsets(from: origin, to: frame, direction: direction) else {
                continue
            }
            guard let current = best else {
                best = (index, offsets.along, offsets.across)
                continue
            }
            if offsets.along < current.along
                || (offsets.along == current.along && offsets.across < current.across) {
                best = (index, offsets.along, offsets.across)
            }
        }

        return best?.index
    }

    /// How far a candidate sits in the requested direction, or `nil` when it is not
    /// a neighbour in that direction at all.
    ///
    /// A candidate must both lie beyond the origin along the travel axis and share
    /// a span with it across that axis. Without the second requirement, moving down
    /// out of a top-right zone would land in a tall zone on the far side of the
    /// display simply because its center is slightly lower.
    private static func travelOffsets(
        from origin: CGRect,
        to candidate: CGRect,
        direction: ZoneDirection
    ) -> (along: CGFloat, across: CGFloat)? {
        let horizontal = candidate.midX - origin.midX
        let vertical = candidate.midY - origin.midY
        // Centers closer together than this count as level rather than offset, which
        // keeps zone gaps and rounding from registering as a direction.
        let threshold: CGFloat = 0.5

        let overlapsVertically = candidate.maxY > origin.minY + threshold
            && candidate.minY < origin.maxY - threshold
        let overlapsHorizontally = candidate.maxX > origin.minX + threshold
            && candidate.minX < origin.maxX - threshold

        switch direction {
        case .left:
            guard horizontal < -threshold, overlapsVertically else { return nil }
            return (-horizontal, abs(vertical))
        case .right:
            guard horizontal > threshold, overlapsVertically else { return nil }
            return (horizontal, abs(vertical))
        case .up:
            guard vertical > threshold, overlapsHorizontally else { return nil }
            return (vertical, abs(horizontal))
        case .down:
            guard vertical < -threshold, overlapsHorizontally else { return nil }
            return (-vertical, abs(horizontal))
        }
    }

    private static func squaredCenterDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let dx = first.midX - second.midX
        let dy = first.midY - second.midY
        return (dx * dx) + (dy * dy)
    }
}
