import UIKit

public protocol DialControlDelegate: AnyObject {
    func dialControl(_ dial: DialControlView, didSelectIndex index: Int, value: String)
}

public final class DialControlView: UIView {
    
    // MARK: - Configuration
    public weak var delegate: DialControlDelegate?
    
    private var values: [String] = []
    private var currentIndex: Int = 0
    
    // Haptics
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let centerIndicator = UIView()
    private let itemWidth: CGFloat = 64.0
    
    // MARK: - Initializer
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = UIColor(white: 0.05, alpha: 0.9)
        layer.cornerRadius = 12.0
        layer.borderWidth = 1.0
        layer.borderColor = UIColor(white: 0.18, alpha: 1.0).cgColor
        layer.masksToBounds = true
        
        // Scroll View
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        // Stack View
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        
        // Center Reticle / Indicator (Amber Leica/Fuji style)
        centerIndicator.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        centerIndicator.layer.cornerRadius = 1.5
        centerIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerIndicator)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            
            centerIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            centerIndicator.widthAnchor.constraint(equalToConstant: 24),
            centerIndicator.heightAnchor.constraint(equalToConstant: 3)
        ])
        
        hapticFeedback.prepare()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // Content inset to center the first and last elements
        let sideInset = (bounds.width - itemWidth) / 2.0
        scrollView.contentInset = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
    }
    
    // MARK: - Public Methods
    public func setValues(_ newValues: [String], defaultIndex: Int = 0) {
        self.values = newValues
        
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for (idx, val) in newValues.enumerated() {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.widthAnchor.constraint(equalToConstant: itemWidth).isActive = true
            
            // Text Label
            let label = UILabel()
            label.text = val
            label.textAlignment = .center
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = UIColor(white: 0.6, alpha: 1.0)
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            
            // Tick mark
            let tick = UIView()
            let isMajorTick = (idx % 3 == 0)
            tick.backgroundColor = isMajorTick ? UIColor.white.withAlphaComponent(0.8) : UIColor.white.withAlphaComponent(0.3)
            tick.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tick)
            
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                
                tick.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                tick.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
                tick.widthAnchor.constraint(equalToConstant: isMajorTick ? 1.5 : 1.0),
                tick.heightAnchor.constraint(equalToConstant: isMajorTick ? 8 : 4)
            ])
            
            stackView.addArrangedSubview(container)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.selectIndex(defaultIndex, animated: false)
        }
    }
    
    public func selectIndex(_ index: Int, animated: Bool) {
        guard index >= 0, index < values.count else { return }
        currentIndex = index
        let targetX = CGFloat(index) * itemWidth - scrollView.contentInset.left
        scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
        updateLabelsHighlight()
    }
    
    private func updateLabelsHighlight() {
        for (i, view) in stackView.arrangedSubviews.enumerated() {
            if let label = view.subviews.first(where: { $0 is UILabel }) as? UILabel {
                let isSelected = (i == currentIndex)
                label.textColor = isSelected ? UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0) : UIColor(white: 0.5, alpha: 1.0)
                label.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: isSelected ? .bold : .medium)
            }
        }
    }
}

// MARK: - UIScrollViewDelegate
extension DialControlView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x + scrollView.contentInset.left
        let rawIndex = Int(round(offsetX / itemWidth))
        let clampedIndex = max(0, min(values.count - 1, rawIndex))
        
        if clampedIndex != currentIndex {
            currentIndex = clampedIndex
            hapticFeedback.impactOccurred(intensity: 0.7)
            updateLabelsHighlight()
            delegate?.dialControl(self, didSelectIndex: currentIndex, value: values[currentIndex])
        }
    }
    
    public func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let proposedX = targetContentOffset.pointee.x + scrollView.contentInset.left
        let rawIndex = round(proposedX / itemWidth)
        let clampedIndex = max(0, min(CGFloat(values.count - 1), rawIndex))
        let snappedX = (clampedIndex * itemWidth) - scrollView.contentInset.left
        targetContentOffset.pointee = CGPoint(x: snappedX, y: 0)
    }
}
