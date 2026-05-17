import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    @State private var auth: AuthService
    @State private var sync: SyncService
    @State private var realtime: RealtimeService
    let container: ModelContainer

    init() {
        let container = RoamModelContainer.make()
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
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

private struct AppShell: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                SplashView()
            case .signedOut:
                AuthView()
            case .signedIn:
                RootView()
            }
        }
        .animation(.easeOut(duration: 0.18), value: auth.phase)
    }
}
