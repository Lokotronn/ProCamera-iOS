import UIKit

public final class ExposureReadoutView: UIView {
    
    // UI Labels
    private let shutterLabel = UILabel()
    private let isoLabel = UILabel()
    private let lensApertureLabel = UILabel()
    private let evLabel = UILabel()
    private let focusDistanceLabel = UILabel()
    
    // Status Badges
    private let aelBadge = UILabel()
    private let aflBadge = UILabel()
    private let formatBadge = UILabel()
    
    // MARK: - Initializer
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor(white: 0.05, alpha: 0.85)
        layer.cornerRadius = 10.0
        layer.borderWidth = 1.0
        layer.borderColor = UIColor(white: 0.18, alpha: 1.0).cgColor
        
        // Setup monospaced telemetry labels
        configureLabel(shutterLabel, text: "1/125s", isPrimary: true)
        configureLabel(isoLabel, text: "ISO 100", isPrimary: true)
        configureLabel(lensApertureLabel, text: "24mm ƒ/1.8", isPrimary: false)
        configureLabel(evLabel, text: "+0.0 EV", isPrimary: false)
        configureLabel(focusDistanceLabel, text: "INF", isPrimary: false)
        
        // Badges
        configureBadge(aelBadge, text: "AEL")
        configureBadge(aflBadge, text: "AFL")
        configureBadge(formatBadge, text: "ProRAW", activeColor: UIColor.systemOrange)
        
        // Main horizontal layout
        let topStack = UIStackView(arrangedSubviews: [shutterLabel, isoLabel, lensApertureLabel])
        topStack.axis = .horizontal
        topStack.distribution = .equalSpacing
        topStack.alignment = .center
        
        let bottomStack = UIStackView(arrangedSubviews: [evLabel, focusDistanceLabel, aelBadge, aflBadge, formatBadge])
        bottomStack.axis = .horizontal
        bottomStack.spacing = 8
        bottomStack.alignment = .center
        
        let containerStack = UIStackView(arrangedSubviews: [topStack, bottomStack])
        containerStack.axis = .vertical
        containerStack.spacing = 6
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerStack)
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }
    
    private func configureLabel(_ label: UILabel, text: String, isPrimary: Bool) {
        label.text = text
        label.font = UIFont.monospacedDigitSystemFont(ofSize: isPrimary ? 15 : 12, weight: isPrimary ? .bold : .medium)
        label.textColor = isPrimary ? .white : UIColor(white: 0.7, alpha: 1.0)
    }
    
    private func configureBadge(_ label: UILabel, text: String, activeColor: UIColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)) {
        label.text = " \(text) "
        label.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        label.textColor = UIColor(white: 0.35, alpha: 1.0)
        label.layer.borderColor = UIColor(white: 0.25, alpha: 1.0).cgColor
        label.layer.borderWidth = 1.0
        label.layer.cornerRadius = 3.0
        label.layer.masksToBounds = true
    }
    
    // MARK: - Update with Telemetry
    public func update(with telemetry: CameraTelemetry) {
        shutterLabel.text = telemetry.formattedShutterSpeed
        isoLabel.text = telemetry.formattedISO
        lensApertureLabel.text = "\(telemetry.activeLens.focalLengthEquivalent) \(telemetry.formattedAperture)"
        evLabel.text = telemetry.formattedEV
        focusDistanceLabel.text = telemetry.formattedLensPosition
        
        // AEL indicator
        if telemetry.isExposureLocked {
            aelBadge.textColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
            aelBadge.layer.borderColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0).cgColor
            aelBadge.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.15)
        } else {
            aelBadge.textColor = UIColor(white: 0.35, alpha: 1.0)
            aelBadge.layer.borderColor = UIColor(white: 0.25, alpha: 1.0).cgColor
            aelBadge.backgroundColor = .clear
        }
        
        // AFL indicator
        if telemetry.isFocusLocked {
            aflBadge.textColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
            aflBadge.layer.borderColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0).cgColor
            aflBadge.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.15)
        } else {
            aflBadge.textColor = UIColor(white: 0.35, alpha: 1.0)
            aflBadge.layer.borderColor = UIColor(white: 0.25, alpha: 1.0).cgColor
            aflBadge.backgroundColor = .clear
        }
        
        // Format
        formatBadge.text = " \(telemetry.currentFormat.rawValue) "
        formatBadge.textColor = UIColor(white: 0.9, alpha: 1.0)
        formatBadge.layer.borderColor = UIColor.systemOrange.cgColor
    }
}
