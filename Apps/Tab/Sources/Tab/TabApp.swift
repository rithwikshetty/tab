import SwiftUI
import SwiftData

@main
struct TabApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var realtime: RealtimeService
    @State private var push = PushService.shared
    let container: ModelContainer

    init() {
        let container = TabModelContainer.make()
        let auth = AuthService()
        let sync = SyncService(container: container, auth: auth)
        let realtime = RealtimeService(sync: sync)
        self.container = container
        _auth = State(initialValue: auth)
        _sync = State(initialValue: sync)
        _realtime = State(initialValue: realtime)
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(auth)
                .environment(sync)
                .environment(realtime)
                .environment(push)
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

private struct AppShell: View {
    @Environment(AuthService.self) private var auth
    @State private var splashAnimationDone = false

    private var isLoading: Bool {
        if case .loading = auth.phase { return true }
        return false
    }

    private var showSplash: Bool {
        !splashAnimationDone || isLoading
    }

    var body: some View {
        ZStack {
            Group {
                switch auth.phase {
                case .loading:
                    Sage.bg.ignoresSafeArea()
                case .signedOut:
                    AuthView()
                case .signedIn:
                    RootView()
                }
            }

            if showSplash {
                SplashView(onAnimationComplete: { splashAnimationDone = true })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onOpenURL { url in
            auth.handleAuthCallback(url)
        }
        .animation(.easeOut(duration: 0.35), value: splashAnimationDone)
        .animation(.easeOut(duration: 0.35), value: isLoading)
    }
}
