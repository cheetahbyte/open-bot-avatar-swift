import Foundation

/// An sRGB color, written `#rgb` or `#rrggbb` in hex.
public struct AvatarColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public static let defaultBody = AvatarColor(red: 0xFF, green: 0x6A, blue: 0x1A)
    public static let defaultEyes = AvatarColor(red: 0x15, green: 0x15, blue: 0x15)

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else { return nil }
        var digits = Array(trimmed.dropFirst())
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isHexDigit) else {
            return nil
        }
        if digits.count == 3 { digits = digits.flatMap { [$0, $0] } }
        guard let value = UInt32(String(digits), radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }
}
