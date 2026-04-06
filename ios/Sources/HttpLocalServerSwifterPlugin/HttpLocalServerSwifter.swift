import Foundation
import Swifter
import Capacitor

public protocol HttpLocalServerSwifterDelegate: AnyObject {
    func httpLocalServerSwifterDidReceiveRequest(_ data: [String: Any])
}

@objc public class HttpLocalServerSwifter: NSObject {
    private var webServer: HttpServer?
    private weak var delegate: HttpLocalServerSwifterDelegate?

    private static var pendingResponses = [String: (String) -> Void]()
    private static let queue = DispatchQueue(
        label: "com.cappitolian.HttpLocalServerSwifter.pendingResponses",
        qos: .userInitiated
    )

    private let defaultTimeout: TimeInterval = 10.0
    private let defaultPort: UInt16 = 8080

    public init(delegate: HttpLocalServerSwifterDelegate) {
        self.delegate = delegate
        super.init()
    }

    // MARK: - Public API

    @objc public func connect(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            self.stopServer()

            let server = HttpServer()
            self.webServer = server

            server.middleware.append { [weak self] request in
                guard let self else { return .raw(503, "Service Unavailable", nil, nil) }

                if request.method == "OPTIONS" {
                    return self.corsResponse()
                }
                return self.processRequest(request)
            }

            do {
                try server.start(self.defaultPort, forceIPv4: true)
                let ip = Self.getWiFiAddress() ?? "127.0.0.1"

                print("🚀 SWIFTER: Server running on http://\(ip):\(self.defaultPort)")

                call.resolve([
                    "ip": ip,
                    "port": Int(self.defaultPort)
                ])
            } catch {
                print("❌ SWIFTER ERROR: \(error)")
                call.reject("Could not start server: \(error.localizedDescription)")
            }
        }
    }

    /// Stops the server and clears state. Does NOT resolve/reject any call.
    @objc public func stopServer() {
        webServer?.stop()
        webServer = nil
        // Drain pending futures so blocked threads can unblock on their semaphore timeout.
        Self.queue.sync { Self.pendingResponses.removeAll() }
    }

    /// Stops the server and resolves the Capacitor call.
    @objc public func disconnect(resolving call: CAPPluginCall) {
        stopServer()
        call.resolve()
    }

    // MARK: - JS → Native response bridge

    static func handleJsResponse(requestId: String, responseData: [String: Any]) {
        // sync: guarantees the callback executes (and signals the semaphore) before
        // this function returns, which eliminates the race condition where the
        // semaphore wait could time out while the callback is still queued.
        queue.sync {
            guard let callback = pendingResponses.removeValue(forKey: requestId) else { return }

            guard
                let jsonData = try? JSONSerialization.data(withJSONObject: responseData),
                let jsonString = String(data: jsonData, encoding: .utf8)
            else { return }

            callback(jsonString)
        }
    }

    // MARK: - Request processing

    private func processRequest(_ request: HttpRequest) -> HttpResponse {
        let requestId = UUID().uuidString

        // Use a protected local variable written only inside `queue.sync` inside
        // the callback, and read only after the semaphore is signalled — the
        // happens-before guarantee of DispatchSemaphore makes this safe.
        var responseString: String?
        let semaphore = DispatchSemaphore(value: 0)

        Self.queue.sync {
            Self.pendingResponses[requestId] = { jsResponse in
                responseString = jsResponse
                semaphore.signal()
            }
        }

        let requestData: [String: Any] = [
            "requestId": requestId,
            "method":    request.method,
            "path":      request.path,
            "headers":   request.headers,
            "query":     request.queryParams,
            "body":      String(bytes: request.body, encoding: .utf8) ?? ""
        ]

        // notifyListeners MUST be called from the main thread.
        DispatchQueue.main.async {
            self.delegate?.httpLocalServerSwifterDidReceiveRequest(requestData)
        }

        let result = semaphore.wait(timeout: .now() + defaultTimeout)

        if result == .timedOut {
            // Remove callback in case handleJsResponse fires late.
            Self.queue.sync { Self.pendingResponses.removeValue(forKey: requestId) }
            return .raw(408, "Request Timeout", nil, nil)
        }

        return createDynamicResponse(responseString ?? "")
    }

    // MARK: - Response builders

    private func createDynamicResponse(_ jsonResponse: String) -> HttpResponse {
        var finalStatus = 200
        var finalBody   = jsonResponse
        var headers: [String: String] = [
            "Content-Type":                     "application/json",
            "Access-Control-Allow-Origin":      "*",
            "Access-Control-Allow-Methods":     "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers":     "Origin, Content-Type, Accept, Authorization, X-Requested-With"
        ]

        if
            let data = jsonResponse.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            finalBody   = dict["body"]   as? String ?? ""
            finalStatus = dict["status"] as? Int    ?? 200

            if let customHeaders = dict["headers"] as? [String: String] {
                for (key, value) in customHeaders { headers[key] = value }
            }
        }

        return .raw(finalStatus, "OK", headers) { writer in
            try writer.write([UInt8](finalBody.utf8))
        }
    }

    private func corsResponse() -> HttpResponse {
        return .raw(204, "No Content", [
            "Access-Control-Allow-Origin":  "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization, X-Requested-With",
            "Access-Control-Max-Age":       "86400"
        ], nil)
    }

    // MARK: - Network helpers

    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let interface = current.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: interface.ifa_name) == "en0"
            {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                address = String(cString: hostname)
                break
            }
            ptr = interface.ifa_next
        }

        return address
    }
}