import UIKit
import AVFoundation

public final class CameraViewController: UIViewController {
    
    // MARK: - Core Engine
    private let cameraEngine: CameraEngineProtocol
    
    // MARK: - UI Subviews
    private let previewView = CameraPreviewView()
    private let exposureReadoutView = ExposureReadoutView()
    private let histogramView = HistogramView()
    private let dialControl = DialControlView()
    
    // Controls & Dials
    private let shutterButton = UIButton(type: .custom)
    private let lensSegmentedControl = UISegmentedControl(items: ["0.5x", "1.0x", "3.0x"])
    private let modeSegmentedControl = UISegmentedControl(items: ["SS", "ISO", "FOCUS", "EV"])
    
    // Function Buttons
    private let aelButton = UIButton(type: .system)
    private let aflButton = UIButton(type: .system)
    private let peakingButton = UIButton(type: .system)
    private let formatButton = UIButton(type: .system)
    private let autoButton = UIButton(type: .system)
    
    // Flash Overlay (Shutter feedback)
    private let shutterFlashView = UIView()
    
    // Haptic Generators
    private let shutterHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let lockHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let switchHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let notificationHaptic = UINotificationFeedbackGenerator()
    
    // Parameter Lists
    private let shutterValues: [(label: String, time: CMTime)] = [
        ("1/8000", CMTime(value: 1, timescale: 8000)),
        ("1/4000", CMTime(value: 1, timescale: 4000)),
        ("1/2000", CMTime(value: 1, timescale: 2000)),
        ("1/1000", CMTime(value: 1, timescale: 1000)),
        ("1/500",  CMTime(value: 1, timescale: 500)),
        ("1/250",  CMTime(value: 1, timescale: 250)),
        ("1/125",  CMTime(value: 1, timescale: 125)),
        ("1/60",   CMTime(value: 1, timescale: 60)),
        ("1/30",   CMTime(value: 1, timescale: 30)),
        ("1/15",   CMTime(value: 1, timescale: 15)),
        ("1/8",    CMTime(value: 1, timescale: 8)),
        ("1/4",    CMTime(value: 1, timescale: 4)),
        ("1/2",    CMTime(value: 1, timescale: 2)),
        ("1.0s",   CMTime(value: 1, timescale: 1)),
        ("2.0s",   CMTime(value: 2, timescale: 1))
    ]
    
    private let isoValues: [Float] = [50, 64, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200]
    private let focusValues: [(label: String, pos: Float)] = [
        ("0.1m", 0.05), ("0.2m", 0.15), ("0.3m", 0.25), ("0.5m", 0.4),
        ("1.0m", 0.6), ("2.0m", 0.75), ("5.0m", 0.9), ("INF", 1.0)
    ]
    private let evValues: [Float] = [-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0]
    
    private enum DialMode: Int {
        case shutter = 0
        case iso = 1
        case focus = 2
        case ev = 3
    }
    
    private var currentDialMode: DialMode = .shutter
    
    // MARK: - Initializer (Dependency Injection)
    public init(cameraEngine: CameraEngineProtocol = CameraEngine()) {
        self.cameraEngine = cameraEngine
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        self.cameraEngine = CameraEngine()
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupDarkStudioLayout()
        setupActions()
        configureCameraSession()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraEngine.startSession()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraEngine.stopSession()
    }
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - Camera Setup
    private func configureCameraSession() {
        cameraEngine.delegate = self
        previewView.videoPreviewLayer.session = cameraEngine.previewSession
        previewView.delegate = self
        
        // Initial dial configuration
        updateDialForCurrentMode()
    }
    
    // MARK: - UI Layout (Dark Studio Aesthetic)
    private func setupDarkStudioLayout() {
        view.backgroundColor = .black // Pure OLED Black #000000
        
        // 1. Viewfinder Preview View
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // 2. Shutter Flash View (Visual Shutter Click)
        shutterFlashView.backgroundColor = .black
        shutterFlashView.alpha = 0.0
        shutterFlashView.isUserInteractionEnabled = false
        shutterFlashView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterFlashView)
        
        // 3. Top Telemetry Bar
        exposureReadoutView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exposureReadoutView)
        
        // 4. Histogram Floating View
        histogramView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(histogramView)
        
        // 5. Tactical Dial & Selector
        dialControl.delegate = self
        dialControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialControl)
        
        setupModeControl()
        setupLensControl()
        setupFunctionButtons()
        setupShutterButton()
        
        // Layout Constraints
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Viewfinder (4:3 aspect ratio typical for sensor)
            previewView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 50),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor, multiplier: 4.0 / 3.0),
            
            // Flash feedback
            shutterFlashView.edgesAnchor.constraint(equalTo: previewView.edgesAnchor),
            
            // Top Telemetry Header
            exposureReadoutView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 4),
            exposureReadoutView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            exposureReadoutView.trailingAnchor.constraint(equalTo: histogramView.leadingAnchor, constant: -8),
            exposureReadoutView.heightAnchor.constraint(equalToConstant: 44),
            
            // Histogram (Top Right)
            histogramView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 4),
            histogramView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            histogramView.widthAnchor.constraint(equalToConstant: 90),
            histogramView.heightAnchor.constraint(equalToConstant: 44),
            
            // Lens Switcher (Overlaid near bottom of viewfinder)
            lensSegmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lensSegmentedControl.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -12),
            lensSegmentedControl.heightAnchor.constraint(equalToConstant: 28),
            
            // Dial Mode Selector (SS, ISO, FOCUS, EV)
            modeSegmentedControl.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            modeSegmentedControl.heightAnchor.constraint(equalToConstant: 28),
            
            // Stepped Tactile Dial
            dialControl.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 6),
            dialControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            dialControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            dialControl.heightAnchor.constraint(equalToConstant: 48),
            
            // Shutter Button
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -14),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }
    
    private func setupModeControl() {
        modeSegmentedControl.selectedSegmentIndex = 0
        modeSegmentedControl.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        modeSegmentedControl.selectedSegmentTintColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        
        let normalTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.lightGray
        ]
        let selectedTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        modeSegmentedControl.setTitleTextAttributes(normalTextAttributes, for: .normal)
        modeSegmentedControl.setTitleTextAttributes(selectedTextAttributes, for: .selected)
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        modeSegmentedControl.addTarget(self, action: #selector(didChangeDialMode(_:)), for: .valueChanged)
        view.addSubview(modeSegmentedControl)
    }
    
    private func setupLensControl() {
        lensSegmentedControl.selectedSegmentIndex = 1 // 1.0x Wide by default
        lensSegmentedControl.backgroundColor = UIColor(white: 0.05, alpha: 0.75)
        lensSegmentedControl.selectedSegmentTintColor = UIColor(white: 0.3, alpha: 0.8)
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        lensSegmentedControl.setTitleTextAttributes(normalAttrs, for: .normal)
        lensSegmentedControl.setTitleTextAttributes(normalAttrs, for: .selected)
        lensSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        lensSegmentedControl.addTarget(self, action: #selector(didChangeLens(_:)), for: .valueChanged)
        view.addSubview(lensSegmentedControl)
    }
    
    private func setupFunctionButtons() {
        configureTacticalButton(aelButton, title: "AEL")
        configureTacticalButton(aflButton, title: "AFL")
        configureTacticalButton(peakingButton, title: "PEAK")
        configureTacticalButton(formatButton, title: "RAW")
        configureTacticalButton(autoButton, title: "AUTO")
        
        let leftStack = UIStackView(arrangedSubviews: [aelButton, aflButton, peakingButton])
        leftStack.axis = .horizontal
        leftStack.spacing = 8
        leftStack.distribution = .fillEqually
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftStack)
        
        let rightStack = UIStackView(arrangedSubviews: [formatButton, autoButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.distribution = .fillEqually
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightStack)
        
        NSLayoutConstraint.activate([
            leftStack.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            leftStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            leftStack.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -16),
            leftStack.heightAnchor.constraint(equalToConstant: 38),
            
            rightStack.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            rightStack.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 16),
            rightStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rightStack.heightAnchor.constraint(equalToConstant: 38)
        ])
    }
    
    private func configureTacticalButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        button.layer.cornerRadius = 6.0
        button.layer.borderWidth = 1.0
        button.layer.borderColor = UIColor(white: 0.22, alpha: 1.0).cgColor
    }
    
    private func setupShutterButton() {
        shutterButton.backgroundColor = .clear
        shutterButton.layer.cornerRadius = 36.0
        shutterButton.layer.borderWidth = 4.0
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Inner tactile disc
        let innerDisc = UIView()
        innerDisc.backgroundColor = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0) // Leica Red Shutter
        innerDisc.layer.cornerRadius = 28.0
        innerDisc.isUserInteractionEnabled = false
        innerDisc.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addSubview(innerDisc)
        
        NSLayoutConstraint.activate([
            innerDisc.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            innerDisc.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            innerDisc.widthAnchor.constraint(equalToConstant: 56),
            innerDisc.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        shutterButton.addTarget(self, action: #selector(didTapShutter(_:)), for: .touchUpInside)
        view.addSubview(shutterButton)
    }
    
    private func setupActions() {
        aelButton.addTarget(self, action: #selector(didToggleAEL(_:)), for: .touchUpInside)
        aflButton.addTarget(self, action: #selector(didToggleAFL(_:)), for: .touchUpInside)
        peakingButton.addTarget(self, action: #selector(didTogglePeaking(_:)), for: .touchUpInside)
        formatButton.addTarget(self, action: #selector(didToggleFormat(_:)), for: .touchUpInside)
        autoButton.addTarget(self, action: #selector(didTapAutoReset(_:)), for: .touchUpInside)
    }
    
    // MARK: - Actions
    @objc private func didTapShutter(_ sender: UIButton) {
        // Haptic feedback & Physical camera actuation sound/feel
        shutterHaptic.impactOccurred(intensity: 1.0)
        
        // Mechanical curtain flash animation
        UIView.animate(withDuration: 0.05, animations: {
            self.shutterFlashView.alpha = 0.85
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.shutterFlashView.alpha = 0.0
                self.shutterButton.transform = .identity
            }
        }
        
        // Capture through engine
        cameraEngine.capturePhoto()
    }
    
    @objc private func didChangeDialMode(_ sender: UISegmentedControl) {
        switchHaptic.impactOccurred()
        guard let mode = DialMode(rawValue: sender.selectedSegmentIndex) else { return }
        currentDialMode = mode
        updateDialForCurrentMode()
    }
    
    private func updateDialForCurrentMode() {
        switch currentDialMode {
        case .shutter:
            let labels = shutterValues.map { $0.label }
            dialControl.setValues(labels, defaultIndex: 6) // Default 1/125s
        case .iso:
            let labels = isoValues.map { "\(Int($0))" }
            dialControl.setValues(labels, defaultIndex: 2) // Default ISO 100
        case .focus:
            let labels = focusValues.map { $0.label }
            dialControl.setValues(labels, defaultIndex: 7) // Default Infinity
        case .ev:
            let labels = evValues.map { String(format: "%+.1f", $0) }
            dialControl.setValues(labels, defaultIndex: 4) // Default 0.0 EV
        }
    }
    
    @objc private func didChangeLens(_ sender: UISegmentedControl) {
        switchHaptic.impactOccurred()
        let lens: CameraLens
        switch sender.selectedSegmentIndex {
        case 0: lens = .ultraWide
        case 1: lens = .wide
        case 2: lens = .telephoto
        default: lens = .wide
        }
        cameraEngine.switchLens(to: lens)
    }
    
    @objc private func didToggleAEL(_ sender: UIButton) {
        lockHaptic.impactOccurred()
        cameraEngine.lockExposure()
        aelButton.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.3)
    }
    
    @objc private func didToggleAFL(_ sender: UIButton) {
        lockHaptic.impactOccurred()
        cameraEngine.lockFocus()
        aflButton.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.3)
    }
    
    @objc private func didTogglePeaking(_ sender: UIButton) {
        switchHaptic.impactOccurred()
        cameraEngine.isFocusPeakingEnabled.toggle()
        let isEnabled = cameraEngine.isFocusPeakingEnabled
        peakingButton.backgroundColor = isEnabled ? UIColor.systemGreen.withAlphaComponent(0.3) : UIColor(white: 0.12, alpha: 1.0)
    }
    
    @objc private func didToggleFormat(_ sender: UIButton) {
        switchHaptic.impactOccurred()
        let nextFormat: CaptureFormat
        switch cameraEngine.currentFormat {
        case .heic:
            nextFormat = cameraEngine.isAppleProRAWSupported ? .proRAW : .rawDNG
        case .proRAW:
            nextFormat = .rawDNG
        case .rawDNG:
            nextFormat = .heic
        }
        cameraEngine.setCaptureFormat(nextFormat)
        formatButton.setTitle(nextFormat.rawValue, for: .normal)
    }
    
    @objc private func didTapAutoReset(_ sender: UIButton) {
        switchHaptic.impactOccurred()
        cameraEngine.unlockExposureToContinuousAuto()
        cameraEngine.unlockFocusToContinuousAuto()
        aelButton.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        aflButton.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
    }
}

// MARK: - DialControlDelegate
extension CameraViewController: DialControlDelegate {
    public func dialControl(_ dial: DialControlView, didSelectIndex index: Int, value: String) {
        switch currentDialMode {
        case .shutter:
            guard index < shutterValues.count else { return }
            cameraEngine.setManualShutterSpeed(shutterValues[index].time)
        case .iso:
            guard index < isoValues.count else { return }
            cameraEngine.setManualISO(isoValues[index])
        case .focus:
            guard index < focusValues.count else { return }
            cameraEngine.setManualFocus(lensPosition: focusValues[index].pos)
        case .ev:
            guard index < evValues.count else { return }
            cameraEngine.setExposureTargetBias(evValues[index])
        }
    }
}

// MARK: - CameraEngineDelegate
extension CameraViewController: CameraEngineDelegate {
    public func cameraEngine(_ engine: CameraEngineProtocol, didUpdateTelemetry telemetry: CameraTelemetry) {
        exposureReadoutView.update(with: telemetry)
    }
    
    public func cameraEngine(_ engine: CameraEngineProtocol, didOutputHistogram histogram: HistogramData) {
        histogramView.update(with: histogram)
    }
    
    public func cameraEngine(_ engine: CameraEngineProtocol, didProcessVideoFrame pixelBuffer: CVPixelBuffer) {
        // Received real-time frame for custom shaders / focus peaking
    }
    
    public func cameraEngine(_ engine: CameraEngineProtocol, didCapturePhoto result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            notificationHaptic.notificationOccurred(.success)
            print("Successfully captured and saved image at: \(url.path)")
        case .failure(let error):
            notificationHaptic.notificationOccurred(.error)
            print("Capture failed: \(error.localizedDescription)")
        }
    }
    
    public func cameraEngine(_ engine: CameraEngineProtocol, didEncounterError error: Error) {
        print("Camera Engine error: \(error.localizedDescription)")
    }
}

// MARK: - CameraPreviewViewDelegate
extension CameraViewController: CameraPreviewViewDelegate {
    public func cameraPreviewDidTapToFocus(at point: CGPoint) {
        let convertedPoint = previewView.videoPreviewLayer.captureDevicePointOfInterest(for: point)
        // Adjust lens position or auto focus spot meter if desired
        cameraEngine.unlockFocusToContinuousAuto()
        cameraEngine.unlockExposureToContinuousAuto()
        aflButton.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        aelButton.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
    }
}

// MARK: - Layout Helper
extension UIView {
    func edgesAnchor(equalTo guide: UILayoutGuide) -> [NSLayoutConstraint] {
        return [
            topAnchor.constraint(equalTo: guide.topAnchor),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ]
    }
    
    func edgesAnchor(equalTo otherView: UIView) -> [NSLayoutConstraint] {
        return [
            topAnchor.constraint(equalTo: otherView.topAnchor),
            bottomAnchor.constraint(equalTo: otherView.bottomAnchor),
            leadingAnchor.constraint(equalTo: otherView.leadingAnchor),
            trailingAnchor.constraint(equalTo: otherView.trailingAnchor)
        ]
    }
}
