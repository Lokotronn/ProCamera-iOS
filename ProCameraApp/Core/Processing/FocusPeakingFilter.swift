import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

public final class FocusPeakingFilter {
    public let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?
    
    public var threshold: Float = 0.22
    public var peakingColor = simd_float4(0.0, 1.0, 0.4, 1.0) // High-visibility fluorescent green
    
    public init() {
        self.device = MTLCreateSystemDefaultDevice()
        guard let device = self.device else { return }
        
        self.commandQueue = device.makeCommandQueue()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        setupPipeline(with: device)
    }
    
    private func setupPipeline(with device: MTLDevice) {
        guard let defaultLibrary = device.makeDefaultLibrary(),
              let kernelFunction = defaultLibrary.makeFunction(name: "focusPeakingKernel") else {
            // In headless/simulator tests without precompiled Metal library, fallback silently
            return
        }
        
        do {
            pipelineState = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Failed to initialize Metal focus peaking pipeline: \(error)")
        }
    }
    
    public func process(pixelBuffer: CVPixelBuffer, outputTexture: MTLTexture) {
        guard let device = device,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let textureCache = textureCache else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        var currentThreshold = threshold
        encoder.setBytes(&currentThreshold, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&peakingColor, length: MemoryLayout<simd_float4>.size, index: 1)
        
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerGroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
    }
}
