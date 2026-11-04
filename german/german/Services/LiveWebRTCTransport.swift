import Foundation
import WebKit

/// A local, non-navigable WebKit document supplies the platform's WebRTC audio stack.
/// The API key and authenticated HTTP exchange never enter this document.
@MainActor final class LiveWebRTCTransport: NSObject, LiveMediaTransport, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: ((Error) -> Void)?
    let webView: WKWebView
    private var offer: CheckedContinuation<String, Error>?
    private var closed = false
    private var loading = false
    private var fixture: String?
    private static let origin = URL(string: "https://german-practice.invalid")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "live")
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    #if DEBUG
    /// Only synthetic speech is sent. WebKit briefly opens and stops local input to authorize ICE.
    func useFixture(_ wav: Data) { fixture = wav.base64EncodedString() }
    func speakFixture(_ data: Data) async throws {
        _ = try await webView.callAsyncJavaScript("await live.speakFixture(encoded)",
            arguments: ["encoded": data.base64EncodedString()], in: nil, contentWorld: .page)
    }
    #endif

    func prepare() async throws -> String {
        guard !closed else { throw CancellationError() }
        try await MicrophoneCapture.requestPermission()
        guard !closed else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            offer = continuation
            loading = true
            webView.loadHTMLString(LiveWebRTCPage.html, baseURL: Self.origin)
        }
    }
    func accept(_ sdp: String) async throws {
        guard !closed else { throw CancellationError() }
        _ = try await webView.callAsyncJavaScript("await live.accept(sdp)", arguments: ["sdp": sdp], in: nil, contentWorld: .page)
    }
    func setMuted(_ muted: Bool) {
        guard !closed else { return }
        Task { [weak self] in
            guard let self else { return }
            do { _ = try await webView.callAsyncJavaScript("live.mute(muted)", arguments: ["muted": muted], in: nil, contentWorld: .page) }
            catch { if !closed { fail(error) } }
        }
    }
    func testSpeaker() throws {
        guard !closed else { return }
        Task { [weak self] in
            guard let self else { return }
            do { _ = try await webView.callAsyncJavaScript("await live.testSpeaker()", arguments: [:], in: nil, contentWorld: .page) }
            catch { if !closed { fail(PracticeError(message: "Could not play the test sound. Check your sound output.")) } }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true
        offer?.resume(throwing: CancellationError()); offer = nil
        Task { @MainActor [self] in
            // JS stops the microphone and sound immediately, then drains session.closed.
            _ = try? await webView.callAsyncJavaScript("await live.close()", arguments: [:], in: nil, contentWorld: .page)
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "live")
            webView.uiDelegate = nil
            webView.navigationDelegate = nil
        }
    }
    private func fail(_ error: Error) {
        offer?.resume(throwing: error); offer = nil
        onFailure?(error)
        close()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == Self.origin.host,
              let event = message.body as? [String: Any] else { return }
        switch event["type"] as? String {
        case "local.ready":
            Task { [weak self] in
                guard let self, !closed else { return }
                do {
                    let preferred = UserDefaults.standard.string(forKey: "practice.microphoneID") ?? ""
                    let devices = LocalMicrophoneRecorder.devices()
                    let device = devices.first { $0.id == preferred }
                    if !preferred.isEmpty && device == nil && fixture == nil {
                        throw PracticeError(message: "The selected microphone is unavailable. Choose a microphone in Settings.")
                    }
                    let arguments: [String: Any] = ["inputName": device?.name ?? "",
                                                   "outputName": RealtimeReplyPlayer().deviceName,
                                                   "fixture": fixture ?? ""]
                    _ = try await webView.callAsyncJavaScript("await live.prepare(inputName, outputName, fixture)",
                                                              arguments: arguments, in: nil, contentWorld: .page)
                } catch { if !closed { fail(error) } }
            }
        case "local.offer":
            guard let sdp = event["sdp"] as? String else { return }
            offer?.resume(returning: sdp); offer = nil
        case "local.error":
            fail(PracticeError(message: event["message"] as? String ?? "The voice connection failed."))
        default: onEvent?(event)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(!closed && frame.isMainFrame && origin.protocol == "https" && origin.host == Self.origin.host && type == .microphone ? .grant : .deny)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the initial, app-owned HTML may load. No remote pages or child frames.
        if loading && navigationAction.targetFrame?.isMainFrame == true {
            loading = false
            decisionHandler(.allow)
        } else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !closed { fail(PracticeError(message: "Could not load the voice audio component.")) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if !closed { fail(PracticeError(message: "The voice audio component stopped. Please reconnect.")) }
    }
}
