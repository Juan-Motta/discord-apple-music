import Darwin
import Foundation

/// When the current user logged in to this Mac's graphical session (from the system's utmpx log).
public func consoleSessionStart(user: String = NSUserName()) -> Date? {
    setutxent()
    defer { endutxent() }
    var latest: Date?
    while let entry = getutxent() {
        let record = entry.pointee
        guard record.ut_type == USER_PROCESS,
              text(record.ut_line) == "console",
              text(record.ut_user) == user
        else { continue }
        let date = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
        if latest.map({ date > $0 }) ?? true { latest = date }
    }
    return latest
}

/// Reads a fixed-size C char array (as imported into Swift) up to its first NUL.
private func text<T>(_ field: T) -> String {
    withUnsafeBytes(of: field) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
