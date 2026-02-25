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
    private static let queue = DispatchQueue(label: "com.cappitolian.HttpLocalServerSwifter.pendingResponses", qos: .userInitiated)
    
    private let defaultTimeout: TimeInterval = 10.0
    private let defaultPort: UInt16 = 8080
    
    public init(delegate: HttpLocalServerSwifterDelegate) {
        self.delegate = delegate
        super.init()
    }
    
    @objc public func connect(_ call: CAPPluginCall) {
        // IMPORTANT: Move execution to a background thread immediately
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.disconnect()
            let server = HttpServer()
            self.webServer = server
            
            // Use middleware to catch ALL requests and avoid route misses
            server.middleware.append { [weak self] request in
                if request.method == "OPTIONS" {
                    return self?.corsResponse() ?? .raw(204, "No Content", nil, nil)
                }
                return self?.processRequest(request) ?? .raw(500, "Internal Server Error", nil, nil)
            }
            
            do {
                // We start the server. This call is non-blocking in Swifter but 
                // it's safer to do it here.
                try server.start(self.defaultPort, forceIPv4: true)
                let ip = Self.getWiFiAddress() ?? "127.0.0.1"
                
                print("🚀 SWIFTER: Server running on http://\(ip):\(self.defaultPort)")
                
                // Resolve back to Angular
                call.resolve([
                    "ip": ip,
                    "port": Int(self.defaultPort)
                ])
            } catch {
                print("❌ SWIFTER ERROR: \(error)")
                call.reject("Could not start server")
            }
        }
    }
    
    @objc public func disconnect(_ call: CAPPluginCall? = nil) {
        webServer?.stop()
        webServer = nil
        Self.queue.async { Self.pendingResponses.removeAll() }
        call?.resolve()
    }

    private func processRequest(_ request: HttpRequest) -> HttpResponse {
        let requestId = UUID().uuidString
        var responseString: String?
        let semaphore = DispatchSemaphore(value: 0)
        
        Self.queue.async {
            Self.pendingResponses[requestId] = { jsResponse in
                responseString = jsResponse
                semaphore.signal()
            }
        }
        
        let requestData: [String: Any] = [
            "requestId": requestId,
            "method": request.method,
            "path": request.path,
            "headers": request.headers,
            "query": request.queryParams,
            "body": String(bytes: request.body, encoding: .utf8) ?? ""
        ]
        
        // CRITICAL: notifyListeners MUST be called from the Main Thread
        DispatchQueue.main.async {
            self.delegate?.httpLocalServerSwifterDidReceiveRequest(requestData)
        }
        
        let result = semaphore.wait(timeout: .now() + defaultTimeout)
        
        if result == .timedOut {
            Self.queue.async { Self.pendingResponses.removeValue(forKey: requestId) }
            return .raw(408, "Request Timeout", nil, nil)
        }
        
        return createDynamicResponse(responseString ?? "")
    }

    static func handleJsResponse(requestId: String, responseData: [String: Any]) {
        queue.async {
            if let callback = pendingResponses[requestId] {
                // Extract body, status and headers to pass as a JSON string to the semaphore
                if let jsonData = try? JSONSerialization.data(withJSONObject: responseData),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    callback(jsonString)
                }
                pendingResponses.removeValue(forKey: requestId)
            }
        }
    }

    private func createDynamicResponse(_ jsonResponse: String) -> HttpResponse {
        var finalStatus = 200
        var finalBody = jsonResponse
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization, X-Requested-With"
        ]
        
        if let data = jsonResponse.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            finalBody = dict["body"] as? String ?? ""
            finalStatus = dict["status"] as? Int ?? 200
            if let customHeaders = dict["headers"] as? [String: String] {
                for (key, value) in customHeaders { headers[key] = value }
            }
        }
        
        return .raw(finalStatus, "OK", headers) { try $0.write([UInt8](finalBody.utf8)) }
    }

    private func corsResponse() -> HttpResponse {
        return .raw(204, "No Content", [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization, X-Requested-With",
            "Access-Control-Max-Age": "86400"
        ], nil)
    }

    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let interface = ptr!.pointee
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}