import Foundation
import AVFoundation

// MARK: - Lens Configuration
public enum CameraLens: String, CaseIterable {
    case ultraWide = "0.5x"
    case wide = "1.0x"
    case telephoto = "3.0x"
    
    public var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide:
            return .builtInUltraWideCamera
        case .wide:
            return .builtInWideAngleCamera
        case .telephoto:
            return .builtInTelephotoCamera
        }
    }
    
    public var focalLengthEquivalent: String {
        switch self {
        case .ultraWide: return "13mm"
        case .wide: return "24mm"
        case .telephoto: return "77mm"
        }
    }
}

// MARK: - Capture Formats
public enum CaptureFormat: String, CaseIterable {
    case heic = "HEIC"
    case rawDNG = "RAW DNG"
    case proRAW = "ProRAW"
    
    public var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .rawDNG, .proRAW: return "dng"
        }
    }
}

// MARK: - Telemetry & Exposure Metadata
public struct CameraTelemetry: Equatable {
    public var iso: Float
    public var shutterSpeed: CMTime
    public var lensPosition: Float
    public var aperture: Float
    public var exposureTargetBias: Float
    public var isExposureLocked: Bool
    public var isFocusLocked: Bool
    public var activeLens: CameraLens
    public var currentFormat: CaptureFormat
    
    public static var zero: CameraTelemetry {
        CameraTelemetry(
            iso: 100,
            shutterSpeed: CMTime(value: 1, timescale: 125),
            lensPosition: 0.5,
            aperture: 1.8,
            exposureTargetBias: 0.0,
            isExposureLocked: false,
            isFocusLocked: false,
            activeLens: .wide,
            currentFormat: .proRAW
        )
    }
    
    public var formattedShutterSpeed: String {
        let seconds = CMTimeGetSeconds(shutterSpeed)
        guard seconds > 0 else { return "0s" }
        if seconds < 1.0 {
            let denominator = Int(round(1.0 / seconds))
            return "1/\(denominator)"
        } else {
            return String(format: "%.1fs", seconds)
        }
    }
    
    public var formattedISO: String {
        return "ISO \(Int(round(iso)))"
    }
    
    public var formattedLensPosition: String {
        if lensPosition >= 0.98 {
            return "INF"
        }
        return String(format: "%.2fm", lensPosition * 2.0)
    }
    
    public var formattedEV: String {
        let prefix = exposureTargetBias > 0 ? "+" : ""
        return String(format: "\(prefix)%.1f EV", exposureTargetBias)
    }
    
    public var formattedAperture: String {
        return String(format: "ƒ/%.1f", aperture)
    }
}
