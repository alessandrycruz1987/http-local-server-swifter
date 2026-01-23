import Foundation
import Capacitor

/**
* Capacitor plugin for running a local HTTP server on the device.
* Allows receiving HTTP requests and sending responses from JavaScript.
*/
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
    
    // MARK: - Plugin Methods
    
    /**
    * Starts the local HTTP server.
    * @return ip: The server's IP address
    * @return port: The port the server is listening on
    */
    @objc func connect(_ call: CAPPluginCall) {
        if localServer == nil {
            localServer = HttpLocalServerSwifter(delegate: self)
        }
        localServer?.connect(call)
    }
    
    /**
    * Stops the local HTTP server.
    * Cleans up all resources and pending requests.
    */
    @objc func disconnect(_ call: CAPPluginCall) {
        if localServer != nil {
            localServer?.disconnect(call)
        } else {
            call.resolve()
        }
    }
    
    /**
    * Sends a response back to the client that made the request.
    * @param requestId Unique request ID (received in 'onRequest')
    * @param body Response body (typically stringified JSON)
    */
    @objc func sendResponse(_ call: CAPPluginCall) {
        guard let requestId = call.getString("requestId") else {
            call.reject("Missing requestId")
            return
        }
        
        guard let body = call.getString("body") else {
            call.reject("Missing body")
            return
        }
        
        HttpLocalServerSwifter.handleJsResponse(requestId: requestId, body: body)
        call.resolve()
    }
    
    // MARK: - HttpLocalServerSwifterDelegate
    
    /**
    * Delegate method called when the server receives an HTTP request.
    * Notifies JavaScript via the 'onRequest' event.
    */
    public func httpLocalServerSwifterDidReceiveRequest(_ data: [String: Any]) {
        notifyListeners("onRequest", data: data)
    }
}