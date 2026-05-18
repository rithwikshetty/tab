import SwiftUI

/// Trailing-edge swipe-to-delete affordance for a row. Tap the revealed button
/// or full-swipe past the threshold to fire `onTrigger`. Parents own the
/// confirmation alert and the actual mutation.
///
/// The row coexists with a parent `ScrollView`: a `minimumDistance` of 14 plus
/// a horizontal-intent check inside `onChanged` keeps vertical pans owned by
/// the scroll view. Tapping the content while open just closes the row.
struct SwipeToDeleteRow<Content: View>: View {
    var actionLabel: String = "Delete"
    var actionIcon: String = "trash"
    var actionTint: Color = Sage.warning
    var onTap: (() -> Void)?
    var onTrigger: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isOpen: Bool = false
    @State private var didCrossFullSwipe: Bool = false

    private let actionWidth: CGFloat = 88
    private let fullSwipeThreshold: CGFloat = 140

    var body: some View {
        ZStack(alignment: .trailing) {
            actionTint
                .opacity(min(1, abs(offset) / 24))

            actionButton
                .opacity(min(1, abs(offset) / actionWidth))
                .allowsHitTesting(isOpen)

            content()
                .background(Sage.surface)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isOpen {
                        close()
                    } else {
                        onTap?()
                    }
                }
                .offset(x: offset)
                .gesture(swipeGesture)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .accessibilityAction {
                    if isOpen {
                        close()
                    } else {
                        onTap?()
                    }
                }
                .accessibilityAction(named: Text(actionLabel)) { fire() }
        }
        .clipped()
    }

    private var actionButton: some View {
        HStack {
            Spacer()
            Button(action: fire) {
                VStack(spacing: 4) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }

                let base: CGFloat = isOpen ? -actionWidth : 0
                offset = min(0, base + dx)

                if !didCrossFullSwipe && offset <= -fullSwipeThreshold {
                    Haptics.light()
                    didCrossFullSwipe = true
                } else if didCrossFullSwipe && offset > -fullSwipeThreshold {
                    didCrossFullSwipe = false
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let base: CGFloat = isOpen ? -actionWidth : 0

                if abs(dx) < abs(dy) {
                    close()
                    didCrossFullSwipe = false
                    return
                }

                let predictedFinal = base + predicted
                if offset <= -fullSwipeThreshold || predictedFinal <= -fullSwipeThreshold {
                    fire()
                } else if offset <= -actionWidth / 2 {
                    open()
                } else {
                    close()
                }
                didCrossFullSwipe = false
            }
    }

    private func open() {
        Haptics.selection()
        withAnimation(.snappy(duration: 0.18)) { offset = -actionWidth }
        isOpen = true
    }

    private func close() {
        withAnimation(.snappy(duration: 0.18)) { offset = 0 }
        isOpen = false
    }

    private func fire() {
        Haptics.warning()
        close()
        onTrigger()
    }
}

#Preview("SwipeToDeleteRow") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(0..<6) { i in
                SwipeToDeleteRow(
                    onTap: { print("open \(i)") },
                    onTrigger: { print("delete \(i)") }
                ) {
                    HStack {
                        Text("Row \(i + 1)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Sage.text)
                        Spacer()
                        Text("€\(i * 12 + 4).50")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Sage.text)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                Rectangle().fill(Sage.rowDivider).frame(height: 1)
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding()
    }
    .background(Sage.bg)
}
