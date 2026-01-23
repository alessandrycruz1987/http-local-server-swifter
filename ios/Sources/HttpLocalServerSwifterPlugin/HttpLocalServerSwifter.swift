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
        
        // Catch-all handler for all HTTP methods
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
        guard let bodyBytes = request.body else {
            return nil
        }
        
        return String(bytes: bodyBytes, encoding: .utf8)
    }
    
    private func extractHeaders(from request: HttpRequest) -> [String: String] {
        return request.headers
    }
    
    private func extractQuery(from request: HttpRequest) -> [String: String] {
        return request.queryParams
    }
    
    private func createJsonResponse(_ body: String, statusCode: Int = 200) -> HttpResponse {
        var response: HttpResponse
        
        switch statusCode {
        case 200:
            response = .ok(.text(body))
        case 204:
            response = HttpResponse.raw(204, "No Content", [:], nil)
        case 408:
            response = HttpResponse.raw(408, "Request Timeout", [:], { writer in
                try writer.write([UInt8](body.utf8))
            })
        case 500:
            response = .internalServerError
        default:
            response = HttpResponse.raw(statusCode, "Custom Status", [:], { writer in
                try writer.write([UInt8](body.utf8))
            })
        }
        
        // Add CORS headers
        return response.withHeaders([
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Content-Type, Accept, Authorization",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "3600"
        ])
    }
    
    private func corsResponse() -> HttpResponse {
        return createJsonResponse("{}", statusCode: 204)
    }
    
    private func errorResponse() -> HttpResponse {
        return createJsonResponse("{\"error\":\"Server error\"}", statusCode: 500)
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

// MARK: - HttpResponse Extension
extension HttpResponse {
    func withHeaders(_ headers: [String: String]) -> HttpResponse {
        return HttpResponse.raw(self.statusCode(), self.reasonPhrase(), headers, { writer in
            if let bodyData = try? self.content() {
                try writer.write(bodyData)
            }
        })
    }
    
    func statusCode() -> Int {
        switch self {
        case .ok: return 200
        case .created: return 201
        case .accepted: return 202
        case .movedPermanently: return 301
        case .notModified: return 304
        case .badRequest: return 400
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .internalServerError: return 500
        case .raw(let code, _, _, _): return code
        default: return 200
        }
    }
    
    func reasonPhrase() -> String {
        switch self {
        case .ok: return "OK"
        case .created: return "Created"
        case .accepted: return "Accepted"
        case .movedPermanently: return "Moved Permanently"
        case .notModified: return "Not Modified"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .internalServerError: return "Internal Server Error"
        case .raw(_, let phrase, _, _): return phrase
        default: return "OK"
        }
    }
    
    func content() throws -> [UInt8] {
        switch self {
        case .ok(let body), .created(let body), .accepted(let body):
            return try bodyToBytes(body)
        case .badRequest(let body), .notFound(let body), .internalServerError:
            if let body = body {
                return try bodyToBytes(body)
            }
            return []
        case .raw(_, _, _, let writer):
            var data = [UInt8]()
            let mockWriter = MockResponseWriter { bytes in
                data.append(contentsOf: bytes)
            }
            try writer?(mockWriter)
            return data
        default:
            return []
        }
    }
    
    private func bodyToBytes(_ body: HttpResponseBody) throws -> [UInt8] {
        switch body {
        case .text(let string):
            return [UInt8](string.utf8)
        case .html(let string):
            return [UInt8](string.utf8)
        case .json(let object):
            let data = try JSONSerialization.data(withJSONObject: object)
            return [UInt8](data)
        case .data(let data, _):
            return [UInt8](data)
        case .custom(let writer):
            var bytes = [UInt8]()
            let mockWriter = MockResponseWriter { data in
                bytes.append(contentsOf: data)
            }
            try writer(mockWriter)
            return bytes
        }
    }
}

// MARK: - Mock Response Writer
private class MockResponseWriter: HttpResponseBodyWriter {
    let writeHandler: ([UInt8]) -> Void
    
    init(writeHandler: @escaping ([UInt8]) -> Void) {
        self.writeHandler = writeHandler
    }
    
    func write(_ data: [UInt8]) throws {
        writeHandler(data)
    }
    
    func write(_ data: ArraySlice<UInt8>) throws {
        writeHandler(Array(data))
    }
    
    func write(_ data: NSData) throws {
        var bytes = [UInt8](repeating: 0, count: data.length)
        data.getBytes(&bytes, length: data.length)
        writeHandler(bytes)
    }
    
    func write(_ data: Data) throws {
        writeHandler([UInt8](data))
    }
}