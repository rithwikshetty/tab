import SwiftUI
import SwiftData

@main
struct TabApp: App {
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var realtime: RealtimeService
    @State private var invites: InviteService
    let container: ModelContainer

    init() {
        let container = TabModelContainer.make()
        let auth = AuthService()
        let sync = SyncService(container: container, auth: auth)
        let realtime = RealtimeService(sync: sync)
        let invites = InviteService()
        self.container = container
        _auth = State(initialValue: auth)
        _sync = State(initialValue: sync)
        _realtime = State(initialValue: realtime)
        _invites = State(initialValue: invites)
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(auth)
                .environment(sync)
                .environment(realtime)
                .environment(invites)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    invites.handleOpenURL(url)
                }
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
        .animation(.easeOut(duration: 0.35), value: splashAnimationDone)
        .animation(.easeOut(duration: 0.35), value: isLoading)
    }
}
