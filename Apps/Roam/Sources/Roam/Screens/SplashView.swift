import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("roam")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-1.4)
                .foregroundStyle(Sage.text)
            ProgressView()
                .tint(Sage.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Sage.bg.ignoresSafeArea())
    }
}

#Preview {
    SplashView()
}
