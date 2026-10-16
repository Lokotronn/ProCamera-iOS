import Foundation
import AVFoundation
import Photos
import UIKit

public final class CameraEngine: NSObject, CameraEngineProtocol {
    
    // MARK: - Properties & State
    public weak var delegate: CameraEngineDelegate?
    public let previewSession: AVCaptureSession = AVCaptureSession()
    
    public private(set) var isRunning: Bool = false
    public var isFocusPeakingEnabled: Bool = false
    
    public private(set) var activeLens: CameraLens = .wide
    public private(set) var currentFormat: CaptureFormat = .heic
    
    // Low-Level Hardware
    private var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    
    // Processors
    private let histogramProcessor = HistogramProcessor()
    private let focusPeakingFilter = FocusPeakingFilter()
    
    // Queues
    private let sessionQueue = DispatchQueue(label: "com.procamera.sessionQueue", qos: .userInitiated)
    private let videoDataQueue = DispatchQueue(label: "com.procamera.videoDataQueue", qos: .userInteractive)
    
    // Telemetry throttling
    private var lastTelemetryUpdate: TimeInterval = 0
    private let telemetryInterval: TimeInterval = 1.0 / 10.0 // 10 Hz telemetry update
    
    // In-flight capture callbacks
    private var captureCompletion: ((Result<URL, Error>) -> Void)?
    
    // MARK: - Initialization
    public override init() {
        super.init()
    }
    
    // MARK: - Lifecycle
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else { return }
            
            self.configureSession()
            self.previewSession.startRunning()
            self.isRunning = self.previewSession.isRunning
            self.notifyTelemetry()
        }
    }
    
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRunning else { return }
            
            self.previewSession.stopRunning()
            self.isRunning = false
        }
    }
    
    // MARK: - Session Configuration
    private func configureSession() {
        previewSession.beginConfiguration()
        previewSession.sessionPreset = .photo
        
        // 1. Initial Device Selection (Wide Angle by default)
        guard let device = selectCaptureDevice(for: .wide) else {
            previewSession.commitConfiguration()
            notifyError(CameraError.deviceUnavailable)
            return
        }
        self.currentDevice = device
        
        // 2. Add Device Input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if previewSession.canAddInput(input) {
                previewSession.addInput(input)
                self.currentInput = input
            } else {
                notifyError(CameraError.cannotAddInput)
            }
        } catch {
            notifyError(error)
        }
        
        // 3. Configure Photo Output
        if previewSession.canAddOutput(photoOutput) {
            previewSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
            
            // Check Apple ProRAW support
            if photoOutput.isAppleProRAWSupported {
                photoOutput.isAppleProRAWEnabled = true
                currentFormat = .proRAW
            } else if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                currentFormat = .rawDNG
            }
        }
        
        // 4. Configure Video Data Output for Real-time Analysis
        if previewSession.canAddOutput(videoDataOutput) {
            previewSession.addOutput(videoDataOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        }
        
        previewSession.commitConfiguration()
    }
    
    // MARK: - Device Discovery
    private func selectCaptureDevice(for lens: CameraLens) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [lens.deviceType],
            mediaType: .video,
            position: .back
        )
        return discoverySession.devices.first
    }
    
    public var availableLenses: [CameraLens] {
        var lenses: [CameraLens] = []
        for lens in CameraLens.allCases {
            if selectCaptureDevice(for: lens) != nil {
                lenses.append(lens)
            }
        }
        return lenses
    }
    
    // MARK: - Lens Switching (Optics)
    public func switchLens(to lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self = self, self.activeLens != lens else { return }
            guard let newDevice = self.selectCaptureDevice(for: lens) else {
                self.notifyError(CameraError.lensNotSupported(lens))
                return
            }
            
            self.previewSession.beginConfiguration()
            
            // Remove previous input
            if let currentInput = self.currentInput {
                self.previewSession.removeInput(currentInput)
            }
            
            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if self.previewSession.canAddInput(newInput) {
                    self.previewSession.addInput(newInput)
                    self.currentInput = newInput
                    self.currentDevice = newDevice
                    self.activeLens = lens
                } else {
                    // Re-add old input if new one fails
                    if let old = self.currentInput { self.previewSession.addInput(old) }
                    self.notifyError(CameraError.cannotAddInput)
                }
            } catch {
                self.notifyError(error)
            }
            
            self.previewSession.commitConfiguration()
            self.notifyTelemetry()
        }
    }
    
    // MARK: - Exposure Triangle Controls
    public var minISO: Float {
        currentDevice?.activeFormat.minISO ?? 50.0
    }
    
    public var maxISO: Float {
        currentDevice?.activeFormat.maxISO ?? 3200.0
    }
    
    public var minExposureDuration: CMTime {
        currentDevice?.activeFormat.minExposureDuration ?? CMTime(value: 1, timescale: 10000)
    }
    
    public var maxExposureDuration: CMTime {
        currentDevice?.activeFormat.maxExposureDuration ?? CMTime(value: 1, timescale: 2)
    }
    
    public func setManualISO(_ iso: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: clampedISO) { _ in }
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func setManualShutterSpeed(_ duration: CMTime) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let clampedDuration = self.clampDuration(duration, for: device)
                device.setExposureModeCustom(duration: clampedDuration, iso: AVCaptureDevice.currentISO) { _ in }
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func setManualExposure(iso: Float, duration: CMTime) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                let clampedDuration = self.clampDuration(duration, for: device)
                device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO) { _ in }
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func lockExposure() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            guard device.isExposureModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.exposureMode = .locked
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func unlockExposureToContinuousAuto() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            guard device.isExposureModeSupported(.continuousAutoExposure) else { return }
            do {
                try device.lockForConfiguration()
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func setExposureTargetBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let clampedBias = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(clampedBias) { _ in }
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    private func clampDuration(_ duration: CMTime, for device: AVCaptureDevice) -> CMTime {
        let seconds = CMTimeGetSeconds(duration)
        let minSeconds = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        let maxSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        let clampedSeconds = min(max(seconds, minSeconds), maxSeconds)
        return CMTime(seconds: clampedSeconds, preferredTimescale: 1000000)
    }
    
    // MARK: - Focus Controls
    public var isManualFocusSupported: Bool {
        return currentDevice?.isFocusModeSupported(.locked) ?? false
    }
    
    public func setManualFocus(lensPosition: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            guard device.isFocusModeSupported(.locked) else { return }
            
            do {
                try device.lockForConfiguration()
                let clampedPosition = min(max(lensPosition, 0.0), 1.0)
                device.setFocusModeLocked(lensPosition: clampedPosition) { _ in }
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func lockFocus() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            guard device.isFocusModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = .locked
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    public func unlockFocusToContinuousAuto() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            guard device.isFocusModeSupported(.continuousAutoFocus) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
                self.notifyTelemetry()
            } catch {
                self.notifyError(error)
            }
        }
    }
    
    // MARK: - Format & RAW Capture
    public var isAppleProRAWSupported: Bool {
        return photoOutput.isAppleProRAWSupported
    }
    
    public func setCaptureFormat(_ format: CaptureFormat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            switch format {
            case .proRAW:
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                    self.currentFormat = .proRAW
                } else {
                    self.currentFormat = .heic
                }
            case .rawDNG:
                if !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                    self.photoOutput.isAppleProRAWEnabled = false
                    self.currentFormat = .rawDNG
                } else {
                    self.currentFormat = .heic
                }
            case .heic:
                self.photoOutput.isAppleProRAWEnabled = false
                self.currentFormat = .heic
            }
            self.notifyTelemetry()
        }
    }
    
    public func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            var photoSettings: AVCapturePhotoSettings
            
            switch self.currentFormat {
            case .proRAW:
                guard self.photoOutput.isAppleProRAWSupported,
                      let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                          $0 == kCVPixelFormatType_14Bayer_RGGB || $0 == kCVPixelFormatType_14Bayer_BGGR
                      }) ?? self.photoOutput.availableRawPhotoPixelFormatTypes.first else {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    break
                }
                photoSettings = AVCapturePhotoSettings(
                    rawPhotoPixelFormatType: rawFormat,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            case .rawDNG:
                guard let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    break
                }
                photoSettings = AVCapturePhotoSettings(
                    rawPhotoPixelFormatType: rawFormat,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            case .heic:
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            photoSettings.photoQualityPrioritization = .quality
            if let previewFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewFormatType]
            }
            
            // Trigger capture
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    // MARK: - Telemetry Readout
    private func notifyTelemetry() {
        guard let device = currentDevice else { return }
        let telemetry = CameraTelemetry(
            iso: device.iso,
            shutterSpeed: device.exposureDuration,
            lensPosition: device.lensPosition,
            aperture: device.lensAperture,
            exposureTargetBias: device.exposureTargetBias,
            isExposureLocked: device.exposureMode == .locked,
            isFocusLocked: device.focusMode == .locked,
            activeLens: activeLens,
            currentFormat: currentFormat
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraEngine(self, didUpdateTelemetry: telemetry)
        }
    }
    
    private func notifyError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraEngine(self, didEncounterError: error)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. Process Real-Time Histogram via vImage Accelerate
        if let histogram = histogramProcessor.process(pixelBuffer: pixelBuffer) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraEngine(self, didOutputHistogram: histogram)
            }
        }
        
        // 2. Telemetry polling (10 Hz)
        let now = CACurrentMediaTime()
        if now - lastTelemetryUpdate >= telemetryInterval {
            lastTelemetryUpdate = now
            notifyTelemetry()
        }
        
        // 3. Process Focus Peaking Frame if enabled
        if isFocusPeakingEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraEngine(self, didProcessVideoFrame: pixelBuffer)
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraEngine: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraEngine(self, didCapturePhoto: .failure(error))
            }
            return
        }
        
        guard let fileData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraEngine(self, didCapturePhoto: .failure(CameraError.emptyCaptureData))
            }
            return
        }
        
        // Save to Temporary file and Camera Roll
        let filename = "PRO_\(Int(Date().timeIntervalSince1970)).\(photo.isRawPhoto ? "dng" : "heic")"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try fileData.write(to: tempURL)
            
            // Save to Photo Library asynchronously
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.cameraEngine(self, didCapturePhoto: .success(tempURL))
                    }
                    return
                }
                
                PHPhotoLibrary.shared().performChanges({
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: photo.isRawPhoto ? .photo : .photo, data: fileData, options: nil)
                }) { success, saveError in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if let saveError = saveError {
                            self.delegate?.cameraEngine(self, didCapturePhoto: .failure(saveError))
                        } else {
                            self.delegate?.cameraEngine(self, didCapturePhoto: .success(tempURL))
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraEngine(self, didCapturePhoto: .failure(error))
            }
        }
    }
}

// MARK: - Camera Errors
public enum CameraError: LocalizedError {
    case deviceUnavailable
    case cannotAddInput
    case lensNotSupported(CameraLens)
    case emptyCaptureData
    
    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "El dispositivo de cámara solicitado no está disponible en este hardware."
        case .cannotAddInput:
            return "No se pudo agregar la entrada de cámara a la sesión de captura."
        case .lensNotSupported(let lens):
            return "La lente \(lens.rawValue) no está soportada en este modelo de iPhone."
        case .emptyCaptureData:
            return "Error al procesar los datos de la captura fotográfica."
        }
    }
}
