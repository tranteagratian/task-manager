import SwiftUI

/// The app icon, drawn in code so it lives in the repository as source
/// rather than a binary asset. The mark is the live performance line from
/// the Performance tab — the one piece of this app that has no Windows
/// equivalent to copy, because it is just what the app actually shows.
struct AppIconView: View {
    private let canvas: CGFloat = 1024
    private var inset: CGFloat { canvas * 0.098 }
    private var side: CGFloat { canvas - inset * 2 }

    private var points: [CGPoint] {
        let w = side * 0.66
        let h = side * 0.40
        let xs: [CGFloat] = [0, 0.16, 0.30, 0.46, 0.60, 0.74, 0.86, 1.0]
        let ys: [CGFloat] = [0.10, 0.30, 0.18, 0.62, 0.38, 0.80, 0.55, 0.95]
        return zip(xs, ys).map { CGPoint(x: $0 * w, y: (1 - $1) * h) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.16, blue: 0.20),
                            Color(red: 0.06, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: side * 0.006)
                }
                .frame(width: side, height: side)

            ZStack {
                areaPath
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath
                    .stroke(
                        Color(red: 0.35, green: 0.66, blue: 1.0),
                        style: StrokeStyle(lineWidth: side * 0.032, lineCap: .round, lineJoin: .round)
                    )
            }
            .frame(width: side * 0.66, height: side * 0.40)
        }
        .frame(width: canvas, height: canvas)
    }

    private var linePath: Path {
        var path = Path()
        let pts = points
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// Same polyline, closed down to the baseline so it fills as an area
    /// chart instead of the triangle an unclosed path would produce.
    private var areaPath: Path {
        var path = linePath
        let pts = points
        guard let first = pts.first, let last = pts.last else { return path }
        let bottom = side * 0.40
        path.addLine(to: CGPoint(x: last.x, y: bottom))
        path.addLine(to: CGPoint(x: first.x, y: bottom))
        path.closeSubpath()
        return path
    }
}
