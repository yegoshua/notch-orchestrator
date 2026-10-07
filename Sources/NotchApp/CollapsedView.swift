import SessionCore
import SwiftUI

/// Counters by state to the left of the notch and the usage ring to the right, or both in a
/// top-centre pill on screens without a notch. With no live sessions it draws nothing but the ring.
struct CollapsedView: View {
    @ObservedObject var model: AppModel
    let geometry: NotchGeometry

    private var counters: Counters { model.snapshot.counters }
    private var isVisible: Bool { counters.failed + counters.working + counters.finished > 0 }

    var body: some View {
        Group {
            if geometry.hasNotch {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        countersRow
                            .padding(.horizontal, 10)
                            .frame(width: NotchGeometry.earWidth, alignment: .trailing)
                        Color.clear.frame(width: geometry.notchWidth)
                    }
                    .frame(maxHeight: .infinity)
                    .background(UnevenRoundedRectangle(bottomLeadingRadius: 10).fill(.black))
                    .opacity(isVisible ? 1 : 0)
                    rightEar
                }
            } else {
                HStack(spacing: 10) {
                    if isVisible { countersRow }
                    ring
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(Capsule().fill(.black))
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isVisible)
    }

    // MARK: Right ear: usage ring

    private var ring: some View { LimitRing(window: model.limits.fiveHour) }

    /// Always drawn, also with no live sessions.
    private var rightEar: some View {
        ring
            .padding(.horizontal, 8)
            .frame(width: NotchGeometry.earWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(UnevenRoundedRectangle(bottomTrailingRadius: 10).fill(.black))
    }

    // MARK: Left ear: counters

    private var countersRow: some View {
        HStack(spacing: 8) {
            if counters.failed > 0 {
                counter(counters.failed, color: Self.failedColor) {
                    Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy))
                }
                .accessibilityLabel("\(counters.failed) failed")
            }
            if counters.working > 0 {
                counter(counters.working, color: Self.workingColor) { WorkingMark() }
                    .accessibilityLabel("\(counters.working) working")
            }
            if counters.finished > 0 {
                counter(counters.finished, color: Self.finishedColor) {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy))
                }
                .accessibilityLabel("\(counters.finished) just finished")
            }
        }
        .animation(.easeOut(duration: 0.2), value: counters)
    }

    /// A number next to a state mark. The mark's shape carries the state; colour only supports it.
    private func counter(_ count: Int, color: Color, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 3) {
            mark().foregroundStyle(color).frame(width: 9, height: 9)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(white: 0.92))
                .contentTransition(.numericText())
        }
    }

    private static let failedColor = Color(red: 1.0, green: 0.62, blue: 0.30)
    private static let workingColor = Color(red: 0.45, green: 0.68, blue: 1.0)
    private static let finishedColor = Color(red: 0.45, green: 0.85, blue: 0.55)
}

/// An open ring that turns: "working".
private struct WorkingMark: View {
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}
