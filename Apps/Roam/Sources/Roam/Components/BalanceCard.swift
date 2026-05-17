import SwiftUI

struct BalanceCard: View {
    let label: String
    let amount: String
    let details: [DemoBalanceDetail]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.balanceLabel)
                    .tracking(1.10)
                    .foregroundStyle(Sage.accentStrong.opacity(0.85))
                Text(amount)
                    .font(.balanceAmount)
                    .tracking(-0.85)
                    .foregroundStyle(Sage.accentStrong)
                    .padding(.top, 4)
                    .monospacedDigit()

                if !details.isEmpty {
                    Rectangle()
                        .fill(Sage.accentSoft)
                        .frame(height: 1)
                        .padding(.top, 10)

                    VStack(spacing: 4) {
                        ForEach(details) { detail in
                            HStack {
                                Text(detail.counterparty)
                                    .font(.balanceDetail)
                                    .foregroundStyle(Sage.text.opacity(0.78))
                                Spacer()
                                Text(detail.amount)
                                    .font(.balanceDetail.weight(.semibold))
                                    .foregroundStyle(Sage.text.opacity(0.95))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Glow ornament
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Sage.accentGlow, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .background(Sage.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Sage.accentSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }
}
