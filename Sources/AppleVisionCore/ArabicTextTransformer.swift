import Foundation

public enum ArabicTextTransformer {
    public static func removeHarakat(from text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            !isHarakah(scalar)
        }

        return String(String.UnicodeScalarView(scalars))
    }

    private static func isHarakah(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0610 ... 0x061A,
             0x064B ... 0x065F,
             0x0670,
             0x06D6 ... 0x06ED,
             0x08D3 ... 0x08E1,
             0x08E3 ... 0x08FF:
            return true
        default:
            return false
        }
    }
}
