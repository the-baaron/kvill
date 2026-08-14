import Foundation

/// The document's characters, copied once so the parser can read them.
///
/// Every pass in the parser walks the text a character at a time. Doing that
/// through `NSString.character(at:)` is an Objective-C message send per
/// character, and the string behind a text storage is a rope rather than a flat
/// buffer, so each one has to work out which chunk the index falls in. Copying
/// the whole document into a UTF-16 array first turns all of that into an array
/// subscript. The copy is one `memcpy`; the reads number in the millions.
///
/// Ranges are UTF-16 offsets, the same as everywhere else, so nothing else has
/// to change.
struct Scan {

    let string: NSString
    private let characters: [unichar]

    init(_ string: NSString) {
        self.string = string
        var buffer = [unichar](repeating: 0, count: string.length)
        if !buffer.isEmpty {
            buffer.withUnsafeMutableBufferPointer { pointer in
                string.getCharacters(pointer.baseAddress!,
                                     range: NSRange(location: 0, length: string.length))
            }
        }
        self.characters = buffer
    }

    var length: Int { characters.count }

    @inline(__always)
    func chr(_ index: Int) -> unichar {
        characters[index]
    }

    func substring(with range: NSRange) -> String {
        string.substring(with: range)
    }
}
