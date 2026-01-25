import Foundation
import Capacitor

@objc(HttpLocalServerSwifterPlugin)
public class HttpLocalServerSwifterPlugin: CAPPlugin, CAPBridgedPlugin, HttpLocalServerSwifterDelegate {
    // MARK: - CAPBridgedPlugin Properties
    public let identifier = "HttpLocalServerSwifterPlugin"
    public let jsName = "HttpLocalServerSwifter"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendResponse", returnType: CAPPluginReturnPromise)
    ]
    
    // MARK: - Properties
    private var localServer: HttpLocalServerSwifter?
    
    // MARK: - Lifecycle
    public override func load() {
        print("✅ HttpLocalServerSwifterPlugin: Plugin loaded")
    }
    
    // MARK: - Plugin Methods
    @objc func connect(_ call: CAPPluginCall) {
        print("📞 HttpLocalServerSwifterPlugin: connect() called")
        
        if localServer == nil {
            localServer = HttpLocalServerSwifter(delegate: self)
            print("✅ HttpLocalServerSwifterPlugin: Server instance created")
        }
        
        localServer?.connect(call)
    }
    
    @objc func disconnect(_ call: CAPPluginCall) {
        print("📞 HttpLocalServerSwifterPlugin: disconnect() called")
        
        if localServer != nil {
            localServer?.disconnect(call)
            localServer = nil
        } else {
            call.resolve()
        }
    }
    
    @objc func sendResponse(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId") else {
            print("❌ HttpLocalServerSwifterPlugin: Missing requestId")
            call.reject("Missing requestId")
            return
        }
        
        guard let body = call.getString("body") else {
            print("❌ HttpLocalServerSwifterPlugin: Missing body")
            call.reject("Missing body")
            return
        }
        
        print("📤 HttpLocalServerSwifterPlugin: sendResponse for requestId: \(requestId)")
        HttpLocalServerSwifter.handleJsResponse(requestId: requestId, body: body)
        call.resolve()
    }
    
    // MARK: - HttpLocalServerSwifterDelegate
    public func httpLocalServerSwifterDidReceiveRequest(_ data: [String: Any]) {
        print("📨 HttpLocalServerSwifterPlugin: Received request, notifying listeners")
        print("   Request data: \(data)")
        notifyListeners("onRequest", data: data)
    }
}