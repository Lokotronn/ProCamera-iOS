import UIKit

public final class HistogramView: UIView {
    
    // MARK: - Properties
    private var histogramData: HistogramData = .empty
    
    // UI Elements
    private let shadowClipIndicator = UIView()
    private let highlightClipIndicator = UIView()
    private let titleLabel = UILabel()
    
    // Aesthetic Styling
    private let gridColor = UIColor(white: 0.25, alpha: 0.4)
    private let redChannelColor = UIColor.systemRed.withAlphaComponent(0.65)
    private let greenChannelColor = UIColor.systemGreen.withAlphaComponent(0.65)
    private let blueChannelColor = UIColor.systemBlue.withAlphaComponent(0.65)
    private let lumaChannelColor = UIColor.white.withAlphaComponent(0.85)
    
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
        layer.cornerRadius = 8.0
        layer.borderWidth = 1.0
        layer.borderColor = UIColor(white: 0.2, alpha: 1.0).cgColor
        layer.masksToBounds = true
        
        // Title Label
        titleLabel.text = "RGB HISTOGRAM"
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        titleLabel.textColor = UIColor(white: 0.6, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // Clipping Indicators
        shadowClipIndicator.backgroundColor = .systemBlue
        shadowClipIndicator.layer.cornerRadius = 3.0
        shadowClipIndicator.alpha = 0.0
        shadowClipIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowClipIndicator)
        
        highlightClipIndicator.backgroundColor = .systemRed
        highlightClipIndicator.layer.cornerRadius = 3.0
        highlightClipIndicator.alpha = 0.0
        highlightClipIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightClipIndicator)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            
            shadowClipIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            shadowClipIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            shadowClipIndicator.widthAnchor.constraint(equalToConstant: 6),
            shadowClipIndicator.heightAnchor.constraint(equalToConstant: 6),
            
            highlightClipIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            highlightClipIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightClipIndicator.widthAnchor.constraint(equalToConstant: 6),
            highlightClipIndicator.heightAnchor.constraint(equalToConstant: 6)
        ])
    }
    
    // MARK: - Public Update
    public func update(with data: HistogramData) {
        self.histogramData = data
        
        // Update clipping warning indicators
        UIView.animate(withDuration: 0.15) {
            self.shadowClipIndicator.alpha = data.isShadowClipping ? 1.0 : 0.0
            self.highlightClipIndicator.alpha = data.isHighlightClipping ? 1.0 : 0.0
        }
        
        setNeedsDisplay()
    }
    
    // MARK: - Core Graphics Custom Drawing
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let graphRect = CGRect(x: 4, y: 16, width: rect.width - 8, height: rect.height - 20)
        guard graphRect.width > 0, graphRect.height > 0 else { return }
        
        // 1. Draw Grid lines (25%, 50% 18% middle-gray reference, 75%)
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(0.5)
        
        let verticalSteps: [CGFloat] = [0.25, 0.5, 0.75]
        for step in verticalSteps {
            let x = graphRect.minX + graphRect.width * step
            context.move(to: CGPoint(x: x, y: graphRect.minY))
            context.addLine(to: CGPoint(x: x, y: graphRect.maxY))
        }
        
        let horizontalSteps: [CGFloat] = [0.25, 0.5, 0.75]
        for step in horizontalSteps {
            let y = graphRect.minY + graphRect.height * step
            context.move(to: CGPoint(x: graphRect.minX, y: y))
            context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
        }
        context.strokePath()
        
        // 2. Draw Color Channels with Screen/Additive-like blending
        drawChannel(bins: histogramData.redBins, in: graphRect, color: redChannelColor, context: context)
        drawChannel(bins: histogramData.greenBins, in: graphRect, color: greenChannelColor, context: context)
        drawChannel(bins: histogramData.blueBins, in: graphRect, color: blueChannelColor, context: context)
        
        // 3. Draw Luminance Outline
        drawLuminanceLine(bins: histogramData.luminanceBins, in: graphRect, color: lumaChannelColor, context: context)
    }
    
    private func drawChannel(bins: [Float], in rect: CGRect, color: UIColor, context: CGContext) {
        guard bins.count >= 256 else { return }
        let path = UIBezierPath()
        let stepX = rect.width / CGFloat(255)
        
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        for i in 0..<256 {
            let x = rect.minX + CGFloat(i) * stepX
            let value = CGFloat(bins[i])
            let y = rect.maxY - (value * rect.height)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        
        context.saveGState()
        context.setFillColor(color.cgColor)
        path.fill()
        context.restoreGState()
    }
    
    private func drawLuminanceLine(bins: [Float], in rect: CGRect, color: UIColor, context: CGContext) {
        guard bins.count >= 256 else { return }
        let path = UIBezierPath()
        let stepX = rect.width / CGFloat(255)
        
        for i in 0..<256 {
            let x = rect.minX + CGFloat(i) * stepX
            let value = CGFloat(bins[i])
            let y = rect.maxY - (value * rect.height)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0)
        path.stroke()
        context.restoreGState()
    }
}
