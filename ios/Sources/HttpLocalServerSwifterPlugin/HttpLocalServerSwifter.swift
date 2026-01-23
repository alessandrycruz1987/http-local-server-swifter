import Foundation
import Swifter
import Capacitor

// MARK: - Protocol
public protocol HttpLocalServerSwifterDelegate: AnyObject {
    func httpLocalServerSwifterDidReceiveRequest(_ data: [String: Any])
}

// MARK: - HttpLocalServerSwifter
@objc public class HttpLocalServerSwifter: NSObject {
    // MARK: - Properties
    private var webServer: HttpServer?
    private weak var delegate: HttpLocalServerSwifterDelegate?
    
    private static var pendingResponses = [String: (String) -> Void]()
    private static let queue = DispatchQueue(label: "com.cappitolian.HttpLocalServerSwifter.pendingResponses", qos: .userInitiated)
    
    private let defaultTimeout: TimeInterval = 5.0
    private let defaultPort: UInt16 = 8080
    
    // MARK: - Initialization
    public init(delegate: HttpLocalServerSwifterDelegate) {
        self.delegate = delegate
        super.init()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public Methods
    @objc public func connect(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Server instance deallocated")
                return
            }
            
            // Stop existing server if running
            self.disconnect()
            
            self.webServer = HttpServer()
            self.setupHandlers()
            
            do {
                try self.startServer()
                let ip = Self.getWiFiAddress() ?? "127.0.0.1"
                call.resolve([
                    "ip": ip,
                    "port": self.defaultPort
                ])
            } catch {
                call.reject("Failed to start server: \(error.localizedDescription)")
            }
        }
    }
    
    @objc public func disconnect(_ call: CAPPluginCall? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call?.reject("Server instance deallocated")
                return
            }
            
            self.disconnect()
            call?.resolve()
        }
    }
    
    // MARK: - Static Methods
    static func handleJsResponse(requestId: String, body: String) {
        queue.async {
            if let callback = pendingResponses[requestId] {
                callback(body)
                pendingResponses.removeValue(forKey: requestId)
            }
        }
    }
    
    // MARK: - Private Methods
    private func disconnect() {
        webServer?.stop()
        webServer = nil
        
        // Clear pending responses
        Self.queue.async {
            Self.pendingResponses.removeAll()
        }
    }
    
    private func setupHandlers() {
        guard let server = webServer else { return }
        
        // Catch-all handler for all HTTP methods and paths
        server["/(.*)"] = { [weak self] request in
            guard let self = self else {
                return self?.errorResponse() ?? .internalServerError
            }
            
            // Handle OPTIONS (CORS preflight)
            if request.method == "OPTIONS" {
                return self.corsResponse()
            }
            
            return self.processRequest(request)
        }
    }
    
    private func processRequest(_ request: HttpRequest) -> HttpResponse {
        let method = request.method
        let path = request.path
        let body = extractBody(from: request)
        let headers = extractHeaders(from: request)
        let query = extractQuery(from: request)
        
        let requestId = UUID().uuidString
        var responseString: String?
        
        // Setup semaphore for synchronous waiting
        let semaphore = DispatchSemaphore(value: 0)
        
        Self.queue.async {
            Self.pendingResponses[requestId] = { responseBody in
                responseString = responseBody
                semaphore.signal()
            }
        }
        
        // Notify delegate with request info
        var requestData: [String: Any] = [
            "requestId": requestId,
            "method": method,
            "path": path
        ]
        
        // Only add if they exist (consistent with TypeScript and Android)
        if let body = body, !body.isEmpty {
            requestData["body"] = body
        }
        
        if !headers.isEmpty {
            requestData["headers"] = headers
        }
        
        if !query.isEmpty {
            requestData["query"] = query
        }
        
        delegate?.httpLocalServerSwifterDidReceiveRequest(requestData)
        
        // Wait for JS response or timeout
        let result = semaphore.wait(timeout: .now() + defaultTimeout)
        
        // Cleanup
        Self.queue.async {
            Self.pendingResponses.removeValue(forKey: requestId)
        }
        
        // Handle timeout
        if result == .timedOut {
            let timeoutResponse = "{\"error\":\"Request timeout\",\"requestId\":\"\(requestId)\"}"
            return createJsonResponse(timeoutResponse, statusCode: 408)
        }
        
        let reply = responseString ?? "{\"error\":\"No response from handler\"}"
        return createJsonResponse(reply)
    }
    
    private func extractBody(from request: HttpRequest) -> String? {
        // request.body ya es [UInt8], no es opcional
        let bodyBytes = request.body
    
        guard !bodyBytes.isEmpty else {
            return nil
        }
    
        return String(bytes: bodyBytes, encoding: .utf8)
    }
    
    private func extractHeaders(from request: HttpRequest) -> [String: String] {
        // Swifter headers es [(String, String)], convertir a [String: String]
        var headersDict: [String: String] = [:]
        for (key, value) in request.headers {
            headersDict[key] = value
        }
        return headersDict
    }
    
    private func extractQuery(from request: HttpRequest) -> [String: String] {
    // request.queryParams también es [(String, String)]
        var queryDict: [String: String] = [:]
        for (key, value) in request.queryParams {
            queryDict[key] = value
        }
        return queryDict
    }
    
    private func createJsonResponse(_ body: String, statusCode: Int = 200) -> HttpResponse {
        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "3600"
        ]
        
        let bodyData = [UInt8](body.utf8)
        
        return HttpResponse.raw(statusCode, statusDescription(for: statusCode), headers) { writer in
            try writer.write(bodyData)
        }
    }
    
    private func corsResponse() -> HttpResponse {
        let headers: [String: String] = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "3600"
        ]
        
        return HttpResponse.raw(204, "No Content", headers, nil)
    }
    
    private func errorResponse() -> HttpResponse {
        return createJsonResponse("{\"error\":\"Server error\"}", statusCode: 500)
    }
    
    private func statusDescription(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
    
    private func startServer() throws {
        guard let server = webServer else {
            throw NSError(
                domain: "HttpLocalServerSwifter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WebServer not initialized"]
            )
        }
        
        // Swifter starts on all interfaces (0.0.0.0) by default
        try server.start(defaultPort, forceIPv4: true)
    }
    
    // MARK: - Network Utilities
    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        
        defer {
            freeifaddrs(ifaddr)
        }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check for IPv4 interface
            guard addrFamily == UInt8(AF_INET) else { continue }
            
            let name = String(cString: interface.ifa_name)
            
            // WiFi interface (en0) or cellular (pdp_ip0)
            guard name == "en0" || name == "pdp_ip0" else { continue }
            
            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            
            let result = getnameinfo(
                &addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            
            guard result == 0 else { continue }
            
            address = String(cString: hostname)
            
            // Prefer en0 (WiFi) over pdp_ip0 (cellular)
            if name == "en0" {
                break
            }
        }
        
        return address
    }
}