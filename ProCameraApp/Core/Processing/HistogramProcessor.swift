import Foundation
import CoreVideo
import Accelerate

public final class HistogramProcessor {
    
    // Throttle histogram processing to ~15-20 FPS to conserve GPU/CPU power for capture pipeline
    private var lastProcessedTimestamp: TimeInterval = 0
    private let processingInterval: TimeInterval = 1.0 / 20.0
    
    public init() {}
    
    public func process(pixelBuffer: CVPixelBuffer) -> HistogramData? {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessedTimestamp >= processingInterval else {
            return nil
        }
        lastProcessedTimestamp = currentTime
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        var srcBuffer = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )
        
        // Output buffers for 4 channels (BGRA -> B: index 0, G: index 1, R: index 2, A: index 3)
        var histogramB = [vImagePixelCount](repeating: 0, count: 256)
        var histogramG = [vImagePixelCount](repeating: 0, count: 256)
        var histogramR = [vImagePixelCount](repeating: 0, count: 256)
        var histogramA = [vImagePixelCount](repeating: 0, count: 256)
        
        var histogramPointers: [UnsafeMutablePointer<vImagePixelCount>?] = [
            &histogramB,
            &histogramG,
            &histogramR,
            &histogramA
        ]
        
        let error = histogramPointers.withUnsafeMutableBufferPointer { ptrs in
            vImageHistogramCalculation_ARGB8888(&srcBuffer, ptrs.baseAddress!, 0)
        }
        
        guard error == kvImageNoError else {
            return nil
        }
        
        let totalPixels = Float(width * height)
        guard totalPixels > 0 else { return nil }
        
        // Find maximum peak across channels for relative normalization
        let maxR = Float(histogramR.max() ?? 1)
        let maxG = Float(histogramG.max() ?? 1)
        let maxB = Float(histogramB.max() ?? 1)
        let peakValue = max(maxR, max(maxG, maxB), 1.0)
        
        var normalizedR = [Float](repeating: 0, count: 256)
        var normalizedG = [Float](repeating: 0, count: 256)
        var normalizedB = [Float](repeating: 0, count: 256)
        var normalizedLuma = [Float](repeating: 0, count: 256)
        
        var shadowCount: Float = 0
        var highlightCount: Float = 0
        
        for i in 0..<256 {
            let r = Float(histogramR[i])
            let g = Float(histogramG[i])
            let b = Float(histogramB[i])
            
            normalizedR[i] = r / peakValue
            normalizedG[i] = g / peakValue
            normalizedB[i] = b / peakValue
            
            // Rec. 709 Luminance weights: 0.2126 R + 0.7152 G + 0.0722 B
            let luma = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
            normalizedLuma[i] = min(luma / peakValue, 1.0)
            
            // Track clipping (extreme bins)
            if i <= 2 {
                shadowCount += (r + g + b) / 3.0
            }
            if i >= 253 {
                highlightCount += (r + g + b) / 3.0
            }
        }
        
        // Threshold for clipping alerts (> 2.5% of total pixels in extremes)
        let clipThreshold = totalPixels * 0.025
        let isHighlightClipping = highlightCount > clipThreshold
        let isShadowClipping = shadowCount > clipThreshold
        
        return HistogramData(
            redBins: normalizedR,
            greenBins: normalizedG,
            blueBins: normalizedB,
            luminanceBins: normalizedLuma,
            isHighlightClipping: isHighlightClipping,
            isShadowClipping: isShadowClipping
        )
    }
}
