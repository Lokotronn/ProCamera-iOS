import UIKit
import AVFoundation

public protocol CameraPreviewViewDelegate: AnyObject {
    func cameraPreviewDidTapToFocus(at point: CGPoint)
}

public final class CameraPreviewView: UIView {
    
    // MARK: - Properties
    public weak var delegate: CameraPreviewViewDelegate?
    
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    // Grid Overlay
    private let gridLayer = CAShapeLayer()
    public var isGridEnabled: Bool = true {
        didSet { gridLayer.isHidden = !isGridEnabled }
    }
    
    // Focus Reticle Box
    private let focusBox = UIView()
    
    // MARK: - Initializer
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupPreview()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreview()
    }
    
    private func setupPreview() {
        backgroundColor = .black
        videoPreviewLayer.videoGravity = .resizeAspectFill
        
        // Grid setup
        gridLayer.strokeColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        gridLayer.lineWidth = 0.5
        gridLayer.fillColor = nil
        layer.addSublayer(gridLayer)
        
        // Focus Reticle Box
        focusBox.frame = CGRect(x: 0, y: 0, width: 70, height: 70)
        focusBox.layer.borderColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0).cgColor
        focusBox.layer.borderWidth = 1.0
        focusBox.layer.cornerRadius = 4.0
        focusBox.alpha = 0.0
        addSubview(focusBox)
        
        // Tap Gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        drawGrid()
    }
    
    private func drawGrid() {
        let path = UIBezierPath()
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }
        
        // Vertical lines (Rule of Thirds)
        path.move(to: CGPoint(x: w / 3.0, y: 0))
        path.addLine(to: CGPoint(x: w / 3.0, y: h))
        path.move(to: CGPoint(x: 2.0 * w / 3.0, y: 0))
        path.addLine(to: CGPoint(x: 2.0 * w / 3.0, y: h))
        
        // Horizontal lines (Rule of Thirds)
        path.move(to: CGPoint(x: 0, y: h / 3.0))
        path.addLine(to: CGPoint(x: w, y: h / 3.0))
        path.move(to: CGPoint(x: 0, y: 2.0 * h / 3.0))
        path.addLine(to: CGPoint(x: w, y: 2.0 * h / 3.0))
        
        // Center crosshair
        let center = CGPoint(x: w / 2.0, y: h / 2.0)
        path.move(to: CGPoint(x: center.x - 8, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 8))
        path.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        
        gridLayer.path = path.cgPath
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        showFocusAnimation(at: location)
        delegate?.cameraPreviewDidTapToFocus(at: location)
    }
    
    public func showFocusAnimation(at point: CGPoint) {
        focusBox.center = point
        focusBox.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        focusBox.alpha = 1.0
        
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
            self.focusBox.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.2, options: .curveEaseOut, animations: {
                self.focusBox.alpha = 0.0
            }, completion: nil)
        }
    }
}
