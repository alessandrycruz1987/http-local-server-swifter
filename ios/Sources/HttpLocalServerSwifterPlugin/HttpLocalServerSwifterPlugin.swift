import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(HttpLocalServerSwifterPlugin)
public class HttpLocalServerSwifterPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HttpLocalServerSwifterPlugin"
    public let jsName = "HttpLocalServerSwifter"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = HttpLocalServerSwifter()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
