import Foundation
import Capacitor

@objc(HttpLocalServerSwifterPlugin)
public class HttpLocalServerSwifterPlugin: CAPPlugin, CAPBridgedPlugin, HttpLocalServerSwifterDelegate {
    public let identifier = "HttpLocalServerSwifterPlugin"
    public let jsName = "HttpLocalServerSwifter"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendResponse", returnType: CAPPluginReturnPromise)
    ]
    
    private var localServer: HttpLocalServerSwifter?
    
    @objc func connect(_ call: CAPPluginCall) {
        if localServer == nil { localServer = HttpLocalServerSwifter(delegate: self) }
        localServer?.connect(call)
    }
    
    @objc func disconnect(_ call: CAPPluginCall) {
        localServer?.disconnect(call)
        localServer = nil
    }
    
  @objc func sendResponse(_ call: CAPPluginCall) {
      guard let requestId = call.getString("requestId") else {
          call.reject("Missing requestId")
          return
      }
      
      // Cast dictionaryRepresentation explicitly to [String: Any]
      if let responseData = call.dictionaryRepresentation as? [String: Any] {
          HttpLocalServerSwifter.handleJsResponse(requestId: requestId, responseData: responseData)
          call.resolve()
      } else {
          call.reject("Could not parse response data")
      }
  }
    
    public func httpLocalServerSwifterDidReceiveRequest(_ data: [String: Any]) {
        notifyListeners("onRequest", data: data)
    }
}
