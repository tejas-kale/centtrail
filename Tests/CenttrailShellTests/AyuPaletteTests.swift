@testable import CenttrailShell
import Foundation
import Ledger
import Testing

/// WCAG 2.x contrast ratio between two sRGB hex colours (0xRRGGBB).
private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    func luminance(_ hex: UInt32) -> Double {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { value -> Double in
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    let (lighter, darker) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (lighter + 0.05) / (darker + 0.05)
}

struct AyuPaletteTests {
    @Test(arguments: AyuVariant.allCases)
    func textColoursAreReadableOnBackgroundAndRows(variant: AyuVariant) {
        let palette = variant.palette
        let text: [(String, UInt32)] = [
            ("text", palette.text), ("tint", palette.tint), ("error", palette.error),
            ("positive", palette.positive), ("warning", palette.warning),
        ]
        for (name, colour) in text {
            for (surface, ground) in [("background", palette.background), ("row", palette.row)] {
                #expect(contrast(colour, ground) >= 4.5, "\(variant) \(name) on \(surface)")
            }
        }
    }

    @Test(arguments: AyuVariant.allCases)
    func glyphsOnTheAccentFillAreVisible(variant: AyuVariant) {
        let palette = variant.palette
        #expect(contrast(palette.onAccent, palette.accent) >= 3)
    }

    @Test func darkAppearanceDefaultsToMirage() {
        #expect(AyuVariant.forAppearance(isDark: false, darkChoice: .mirage) == .light)
        #expect(AyuVariant.forAppearance(isDark: true, darkChoice: .mirage) == .mirage)
        #expect(AyuVariant.forAppearance(isDark: true, darkChoice: .dark) == .dark)
        #expect(AyuDarkChoice.default == .mirage)
    }
}

struct RowDateLabelTests {
    private let british = Locale(identifier: "en_GB")

    private func label(_ iso: String) throws -> String {
        let today = try #require(ReportingDate(iso8601: "2026-11-16"))
        return shortDayLabel(try #require(ReportingDate(iso8601: iso)), today: today, locale: british)
    }

    @Test func thisYearsDatesOmitTheYear() throws {
        #expect(try label("2026-11-02") == "2 Nov")
    }

    @Test func earlierYearsKeepTheYear() throws {
        #expect(try label("2025-12-31") == "31 Dec 2025")
    }
}
