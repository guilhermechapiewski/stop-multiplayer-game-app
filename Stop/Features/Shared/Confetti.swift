import SwiftUI

/// Confetti falling from the top for a few seconds; a still scatter with Reduce Motion.
struct ConfettiView: View {
    let isAnimated: Bool

    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, sway: Double
        let size: CGSize, color: Color, isCircle: Bool
    }

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    private static let duration: Double = 4.5

    @State private var start = Date.now
    private let pieces: [Piece] = (0..<90).map { index in
        var rng = SplitMix(seed: UInt64(index) &* 0x9E3779B97F4A7C15)
        return Piece(x: rng.unit, delay: rng.unit * 1.2, speed: 0.55 + rng.unit * 0.5, spin: (rng.unit - 0.5) * 12,
                     sway: rng.unit * 2 * .pi, size: CGSize(width: 6 + rng.unit * 6, height: 9 + rng.unit * 8),
                     color: colors[index % colors.count], isCircle: index % 4 == 0)
    }

    /// The fall is over: stop redrawing.
    @State private var finished = false

    var body: some View {
        if !isAnimated {
            canvas(time: nil)
        } else if !finished {
            TimelineView(.animation) { context in
                canvas(time: context.date.timeIntervalSince(start))
            }
            .task {
                do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
                finished = true
            }
        }
    }

    /// `time` nil draws the still version: pieces scattered across the top fifth, around the trophy and clear
    /// of the title below it.
    private func canvas(time: Double?) -> some View {
        Canvas { context, size in
            for piece in pieces {
                let progress: Double
                let opacity: Double
                if let time {
                    let t = max(0, time - piece.delay)
                    progress = t * piece.speed / 2.2
                    opacity = progress > 1 ? 0 : min(1, (Self.duration - time) / 0.8)
                    if t == 0 { continue }
                } else {
                    progress = piece.delay / 1.2 * 0.18
                    opacity = 0.9
                }
                guard opacity > 0 else { continue }
                let x = piece.x * size.width + sin(progress * 6 + piece.sway) * 18
                let y = -20 + progress * (size.height + 40)
                var pieceContext = context
                pieceContext.opacity = opacity
                pieceContext.translateBy(x: x, y: y)
                pieceContext.rotate(by: .radians(piece.spin * progress + piece.sway))
                let rect = CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)
                let path = piece.isCircle ? Path(ellipseIn: rect.insetBy(dx: 0, dy: (rect.height - rect.width) / 2))
                                          : Path(roundedRect: rect, cornerRadius: 2)
                pieceContext.fill(path, with: .color(piece.color))
            }
        }
    }
}

/// A tiny deterministic generator so the confetti looks the same on every render.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    var unit: Double { mutating get { Double(next() >> 11) / Double(1 << 53) } }
}

#Preview("Confetti") {
    ConfettiView(isAnimated: true)
        .background(Theme.background)
}

#Preview("Confetti – reduce motion") {
    ConfettiView(isAnimated: false)
        .background(Theme.background)
}
