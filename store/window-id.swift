import CoreGraphics
import Foundation
// The id of Kvill's document window, for screencapture -l.
let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Kvill"
        && ((($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0) > 400
}
// The widest one, which is the document window rather than a panel.
let widest = mine.max {
    ((($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0)
        < ((($1[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0)
}
print(widest.flatMap { $0[kCGWindowNumber as String] as? Int }.map(String.init) ?? "")
