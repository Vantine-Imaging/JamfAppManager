import Foundation

/// Reads the Jamf Pro URL this Mac is enrolled to, if any, from the jamf
/// binary's world-readable preferences. Requires the read-only sandbox
/// exception declared in the entitlements.
enum EnrollmentDetector {
    static func enrolledServerURL() -> String? {
        let path = "/Library/Preferences/com.jamfsoftware.jamf.plist"
        guard let dict = NSDictionary(contentsOfFile: path),
              var url = dict["jss_url"] as? String, !url.isEmpty
        else { return nil }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
