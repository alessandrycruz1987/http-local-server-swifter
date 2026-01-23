import Foundation

@objc public class HttpLocalServerSwifter: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
