import Foundation
import AVFoundation
import CoreMedia

// MARK: - Delegate Protocol
public protocol CameraEngineDelegate: AnyObject {
    func cameraEngine(_ engine: CameraEngineProtocol, didUpdateTelemetry telemetry: CameraTelemetry)
    func cameraEngine(_ engine: CameraEngineProtocol, didOutputHistogram histogram: HistogramData)
    func cameraEngine(_ engine: CameraEngineProtocol, didProcessVideoFrame pixelBuffer: CVPixelBuffer)
    func cameraEngine(_ engine: CameraEngineProtocol, didCapturePhoto result: Result<URL, Error>)
    func cameraEngine(_ engine: CameraEngineProtocol, didEncounterError error: Error)
}

// MARK: - Exposure Control Protocol
public protocol CameraExposureControlling: AnyObject {
    var minISO: Float { get }
    var maxISO: Float { get }
    var minExposureDuration: CMTime { get }
    var maxExposureDuration: CMTime { get }
    
    func setManualISO(_ iso: Float)
    func setManualShutterSpeed(_ duration: CMTime)
    func setManualExposure(iso: Float, duration: CMTime)
    func lockExposure()
    func unlockExposureToContinuousAuto()
    func setExposureTargetBias(_ bias: Float)
}

// MARK: - Focus Control Protocol
public protocol CameraFocusControlling: AnyObject {
    var isManualFocusSupported: Bool { get }
    func setManualFocus(lensPosition: Float)
    func lockFocus()
    func unlockFocusToContinuousAuto()
}

// MARK: - Lens & Optical Protocol
public protocol CameraLensControlling: AnyObject {
    var activeLens: CameraLens { get }
    var availableLenses: [CameraLens] { get }
    func switchLens(to lens: CameraLens)
}

// MARK: - Capture & Format Protocol
public protocol CameraCaptureControlling: AnyObject {
    var currentFormat: CaptureFormat { get }
    var isAppleProRAWSupported: Bool { get }
    func setCaptureFormat(_ format: CaptureFormat)
    func capturePhoto()
}

// MARK: - Unified Engine Protocol
public protocol CameraEngineProtocol: AnyObject,
                                      CameraExposureControlling,
                                      CameraFocusControlling,
                                      CameraLensControlling,
                                      CameraCaptureControlling {
    var delegate: CameraEngineDelegate? { get set }
    var previewSession: AVCaptureSession { get }
    var isRunning: Bool { get }
    var isFocusPeakingEnabled: Bool { get set }
    
    func startSession()
    func stopSession()
}
