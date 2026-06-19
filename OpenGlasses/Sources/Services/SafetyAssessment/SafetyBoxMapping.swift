import CoreGraphics

/// Pure mapping from a model `box_2d` (`[ymin, xmin, ymax, xmax]`, normalized 0–1000) to a `CGRect`
/// in a given image/view size — for the HECA evidence-box overlay (tested without SwiftUI).
enum SafetyBoxMapping {
    /// Returns the rect for `box` within `size`, or nil if the box is malformed. Coordinates are
    /// clamped to [0, 1000] and ordered so min ≤ max.
    static func rect(for box: [Int], in size: CGSize) -> CGRect? {
        guard box.count == 4 else { return nil }
        let yMin = clamp(box[0]), xMin = clamp(box[1]), yMax = clamp(box[2]), xMax = clamp(box[3])
        let x0 = CGFloat(min(xMin, xMax)) / 1000 * size.width
        let y0 = CGFloat(min(yMin, yMax)) / 1000 * size.height
        let w = CGFloat(abs(xMax - xMin)) / 1000 * size.width
        let h = CGFloat(abs(yMax - yMin)) / 1000 * size.height
        return CGRect(x: x0, y: y0, width: w, height: h)
    }

    /// Convert a `box_2d` to the substrate's normalized `[x, y, w, h]` (0–1) finding region.
    static func normalizedRegion(for box: [Int]) -> [Double]? {
        guard box.count == 4 else { return nil }
        let yMin = Double(clamp(box[0])), xMin = Double(clamp(box[1]))
        let yMax = Double(clamp(box[2])), xMax = Double(clamp(box[3]))
        return [min(xMin, xMax) / 1000, min(yMin, yMax) / 1000,
                abs(xMax - xMin) / 1000, abs(yMax - yMin) / 1000]
    }

    private static func clamp(_ v: Int) -> Int { max(0, min(1000, v)) }
}
