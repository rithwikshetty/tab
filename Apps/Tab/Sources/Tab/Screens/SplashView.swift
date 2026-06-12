import SwiftUI

struct SplashView: View {
    var onAnimationComplete: () -> Void = {}

    @State private var hasStarted = false
    @State private var wordOpacity: Double = 0
    @State private var wordOffset: CGFloat = 6
    @State private var startScale: CGFloat = 0.4
    @State private var startOpacity: Double = 0
    @State private var curveProgress: CGFloat = 0
    @State private var curveOpacity: Double = 0
    @State private var endScale: CGFloat = 0
    @State private var endOpacity: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            ZStack(alignment: .topLeading) {
                ArcCurveShape()
                    .trim(from: 0, to: curveProgress)
                    .stroke(Sage.markCurve, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 340, height: 80)
                    .opacity(curveOpacity)

                Circle()
                    .strokeBorder(Sage.markStart, lineWidth: 3)
                    .frame(width: 20, height: 20)
                    .scaleEffect(startScale)
                    .opacity(startOpacity)
                    .offset(x: 10, y: 58)

                Circle()
                    .fill(Sage.markEnd)
                    .frame(width: 17, height: 17)
                    .scaleEffect(endScale)
                    .opacity(endOpacity)
                    .offset(x: 311.5, y: 7.5)
            }
            .frame(width: 340, height: 80)

            Text("tab-it")
                .font(.system(size: 44, weight: .medium))
                .tracking(-1.9)
                .foregroundStyle(Sage.text)
                .opacity(wordOpacity)
                .offset(y: wordOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Sage.bg.ignoresSafeArea())
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            runAnimation()
        }
    }

    // The splash gates every launch, so the choreography is kept tight (~1.5s
    // to handoff): same word → dot → curve → dot sequence, compressed.
    private func runAnimation() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.45)) {
                wordOpacity = 1
                wordOffset = 0
            }

            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.easeOut(duration: 0.3)) {
                startOpacity = 1
                startScale = 1
            }

            try? await Task.sleep(for: .seconds(0.2))
            curveOpacity = 1
            withAnimation(.easeOut(duration: 0.8)) {
                curveProgress = 1
            }

            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                endOpacity = 1
                endScale = 1
            }

            try? await Task.sleep(for: .seconds(0.35))
            onAnimationComplete()
        }
    }
}

private struct ArcCurveShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x / 340 * w, y: y / 80 * h)
        }
        path.move(to: p(30, 65))
        path.addCurve(
            to: p(310, 18),
            control1: p(110, 65),
            control2: p(220, 22)
        )
        return path
    }
}

#Preview("Splash") {
    SplashView()
}
