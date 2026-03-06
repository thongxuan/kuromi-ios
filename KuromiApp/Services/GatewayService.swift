import Foundation
import Combine

enum GatewayState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

class GatewayService: NSObject, ObservableObject {
    @Published var state: GatewayState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var gatewayURL: String = ""
    private var gatewayToken: String = ""
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var sessionKey: String = "kuromi-ios-voice"
    private var activeRunId: String? = nil   // only process events matching this runId

    var onResponse: ((String) -> Void)?      // full final text
    var onDelta: ((String) -> Void)?         // streaming delta
    var onResponseComplete: (() -> Void)?    // response finished

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(to urlString: String, token: String = "") {
        gatewayURL = urlString
        gatewayToken = token
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.state = .error("Invalid Gateway URL") }
            return
        }
        DispatchQueue.main.async { self.state = .connecting }
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async { self.state = .disconnected }
    }

    func sendMessage(_ text: String) {
        guard case .connected = state else { return }
        let idempotencyKey = UUID().uuidString
        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": text,
            "idempotencyKey": idempotencyKey,
            "deliver": false
        ]
        sendReq(method: "chat.send", params: params)
    }

    // MARK: - Protocol

    private func sendReq(method: String, params: [String: Any]) {
        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { error in
            if let error = error { print("Gateway send error: \(error)") }
        }
    }

    private func handleChallenge() {
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "openclaw-ios",
                "displayName": "Kuromi iOS",
                "version": "1.0",
                "platform": "ios",
                "mode": "ui"
            ],
            "auth": ["token": gatewayToken],
            "role": "operator",
            "scopes": ["operator.admin"],
            "caps": [] as [String]
        ]
        sendReq(method: "connect", params: params)
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleRawMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleRawMessage(text) }
                @unknown default: break
                }
                self.receiveMessages()
            case .failure(let error):
                print("Gateway receive error: \(error)")
                DispatchQueue.main.async { self.state = .error(error.localizedDescription) }
            }
        }
    }

    private func handleRawMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""
        let event = json["event"] as? String ?? ""

        switch type {
        case "event":
            if event == "connect.challenge" {
                handleChallenge()
            } else if event == "agent" {
                guard let payload = json["payload"] as? [String: Any],
                      let stream = payload["stream"] as? String else { return }

                // Only process events from our own session
                let runId = payload["runId"] as? String
                let evtSession = payload["sessionKey"] as? String
                if let evtSession, !evtSession.contains(sessionKey) { return }
                if let active = activeRunId, runId != active { return }

                if stream == "assistant",
                   let data = payload["data"] as? [String: Any] {
                    if let delta = data["delta"] as? String, !delta.isEmpty {
                        DispatchQueue.main.async { self.onDelta?(delta) }
                    }
                    if let fullText = data["text"] as? String {
                        DispatchQueue.main.async { self.onResponse?(fullText) }
                    }
                } else if stream == "lifecycle",
                          let data = payload["data"] as? [String: Any],
                          let phase = data["phase"] as? String {
                    if phase == "start", let rid = runId { activeRunId = rid }
                    if phase == "end" {
                        activeRunId = nil
                        DispatchQueue.main.async { self.onResponseComplete?() }
                    }
                }
            }
        case "res":
            let ok = json["ok"] as? Bool ?? false
            if ok, let payload = json["payload"] as? [String: Any],
               let runId = payload["runId"] as? String {
                activeRunId = runId  // track runId from chat.send response
            }
            if ok {
                DispatchQueue.main.async { self.state = .connected }
            }
        default:
            break
        }
    }
}

extension GatewayService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // Wait for challenge before marking connected
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { self.state = .disconnected }
    }
}
