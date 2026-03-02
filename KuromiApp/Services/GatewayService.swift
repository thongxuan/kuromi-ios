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
    @Published var lastResponse: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var gatewayURL: String = ""

    var onResponse: ((String) -> Void)?

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(to urlString: String) {
        gatewayURL = urlString
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
        let payload: [String: String] = ["type": "chat.send", "text": text]
        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("Gateway send error: \(error)")
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()
            case .failure(let error):
                print("Gateway receive error: \(error)")
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        if type == "chat.response", let responseText = json["text"] as? String {
            DispatchQueue.main.async {
                self.lastResponse = responseText
                self.onResponse?(responseText)
            }
        }
    }
}

extension GatewayService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.state = .connected }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { self.state = .disconnected }
    }
}
