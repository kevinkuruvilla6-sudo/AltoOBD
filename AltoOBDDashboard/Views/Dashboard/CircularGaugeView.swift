import SwiftUI

/// High-contrast automotive vector gauge with tick marks, optional redline zone, and smooth progress arc.
struct CircularGaugeView: View {
    let title: String
    let value: Double
    let formattedValue: String
    let unit: String
    let minValue: Double
    let maxValue: Double
    var warningThreshold: Double? = nil
    var accentColor: Color = .cyan
    var subtitle: String? = nil

    private let startAngle: Double = 135
    private let sweepAngle: Double = 270

    private var clampedFraction: Double {
        guard maxValue > minValue else { return 0 }
        return min(max((value - minValue) / (maxValue - minValue), 0), 1)
    }

    private var warningFraction: Double? {
        guard let warn = warningThreshold, maxValue > minValue else { return nil }
        return min(max((warn - minValue) / (maxValue - minValue), 0), 1)
    }

    private var activeColor: Color {
        if let warn = warningThreshold, value >= warn {
            return .red
        }
        return accentColor
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = max(10, size * 0.085)

            ZStack {
                // Background track
                ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + sweepAngle))
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Optional redline warning zone
                if let warnFrac = warningFraction {
                    let redStart = startAngle + sweepAngle * warnFrac
                    ArcShape(startAngle: .degrees(redStart), endAngle: .degrees(startAngle + sweepAngle))
                        .stroke(Color.red.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }

                // Active progress arc
                ArcShape(
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle + sweepAngle * clampedFraction)
                )
                .stroke(
                    AngularGradient(
                        colors: [accentColor.opacity(0.75), activeColor],
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + sweepAngle)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .animation(.easeOut(duration: 0.25), value: clampedFraction)

                // Tick marks
                ForEach(0..<19, id: \.self) { idx in
                    let frac = Double(idx) / 18.0
                    let angle = startAngle + sweepAngle * frac
                    let isMajor = idx % 3 == 0
                    let isRed = warningFraction.map { frac >= $0 } ?? false

                    Capsule()
                        .fill(isRed ? Color.red.opacity(0.85) : Color.white.opacity(isMajor ? 0.55 : 0.22))
                        .frame(width: isMajor ? 2.5 : 1.5, height: isMajor ? size * 0.065 : size * 0.035)
                        .offset(y: -(size / 2 - lineWidth - 6))
                        .rotationEffect(.degrees(angle + 90))
                }

                // Center digital readout
                VStack(spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: max(9, size * 0.065), weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1.0)

                    Text(formattedValue)
                        .font(.system(size: max(22, size * 0.22), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text(unit)
                        .font(.system(size: max(10, size * 0.075), weight: .medium, design: .rounded))
                        .foregroundStyle(activeColor)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: max(9, size * 0.062), weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.22), in: Capsule())
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, size * 0.06)
            }
            .padding(lineWidth / 2 + 2)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    var animatableData: Double {
        get { endAngle.degrees }
        set { endAngle = .degrees(newValue) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
