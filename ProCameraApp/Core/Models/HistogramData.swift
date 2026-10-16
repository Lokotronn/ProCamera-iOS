import Foundation

public struct HistogramData {
    public let redBins: [Float]       // Normalized 0.0 - 1.0 (256 elements)
    public let greenBins: [Float]     // Normalized 0.0 - 1.0 (256 elements)
    public let blueBins: [Float]      // Normalized 0.0 - 1.0 (256 elements)
    public let luminanceBins: [Float] // Normalized 0.0 - 1.0 (256 elements)
    
    public let isHighlightClipping: Bool
    public let isShadowClipping: Bool
    
    public static var empty: HistogramData {
        let zeroArray = [Float](repeating: 0.0, count: 256)
        return HistogramData(
            redBins: zeroArray,
            greenBins: zeroArray,
            blueBins: zeroArray,
            luminanceBins: zeroArray,
            isHighlightClipping: false,
            isShadowClipping: false
        )
    }
}
