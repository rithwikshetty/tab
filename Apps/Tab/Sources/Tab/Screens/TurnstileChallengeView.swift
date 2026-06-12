import SwiftUI
import WebKit

/// Cloudflare Turnstile widget in a web view, anchored to the tab-it.app
/// hostname (the widget's allowed-hostname list requires it). Supabase auth
/// rejects email-code requests that don't carry a token from here.
struct TurnstileChallengeView: UIViewRepresentable {
    let siteKey: String
    var onToken: (String) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "turnstile")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(
            Self.widgetHTML(siteKey: siteKey),
            baseURL: URL(string: "https://tab-it.app")!
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstile")
    }

    private static func widgetHTML(siteKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad" async defer></script>
        <style>
          html, body { margin: 0; height: 100%; background: transparent; }
          body { display: flex; align-items: center; justify-content: center; }
        </style>
        </head>
        <body>
        <div id="widget"></div>
        <script>
          function post(event, payload) {
            window.webkit.messageHandlers.turnstile.postMessage({ event: event, payload: payload || "" });
          }
          function onTurnstileLoad() {
            turnstile.render("#widget", {
              sitekey: "\(siteKey)",
              callback: function (token) { post("token", token); },
              "error-callback": function (code) { post("error", String(code)); return true; },
              "expired-callback": function () { turnstile.reset("#widget"); }
            });
          }
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onToken: (String) -> Void
        private let onError: (String) -> Void
        private var finished = false

        init(onToken: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onToken = onToken
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard !finished,
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            let payload = body["payload"] as? String ?? ""

            switch event {
            case "token" where !payload.isEmpty:
                finished = true
                onToken(payload)
            case "error":
                finished = true
                onError(payload)
            default:
                break
            }
        }
    }
}

/// Sheet wrapper: short copy + the widget + cancel. Presented from the email
/// sign-in flow right before a code is requested.
struct TurnstileChallengeSheet: View {
    let siteKey: String
    var onToken: (String) -> Void
    var onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Quick check")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("Confirming you're a person, not a bot.")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
            }
            .padding(.top, 26)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                TurnstileChallengeView(
                    siteKey: siteKey,
                    onToken: onToken,
                    onError: { code in
                        errorMessage = "The check couldn't load (\(code)). Close this and try again."
                    }
                )
                .frame(width: 310, height: 80)
            }

            Button("Cancel") { onCancel() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Sage.textSecondary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Sage.bg)
        .presentationDetents([.height(230)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}
