import AppKit
import SwiftUI
import Testing
@testable import MangoMusic

@MainActor
struct AppearanceTests {
    @Test func modesMapToNativePreferenceAndSystemHasNoOverride() {
        #expect(AppearanceMode.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func appStoragePersistsSelectionAndInvalidValuesFallBackToSystem() throws {
        let suite = "MangoAppearanceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.42, forKey: "volume")
        let setting = AppStorage(wrappedValue: AppearanceMode.system, AppearanceMode.storageKey, store: defaults)
        #expect(setting.wrappedValue == .system)
        for mode in AppearanceMode.allCases {
            setting.wrappedValue = mode
            let restoredDefaults = try #require(UserDefaults(suiteName: suite))
            let restored = AppStorage(wrappedValue: AppearanceMode.system, AppearanceMode.storageKey, store: restoredDefaults)
            #expect(restoredDefaults.string(forKey: AppearanceMode.storageKey) == mode.rawValue)
            #expect(restored.wrappedValue == mode)
            #expect(restoredDefaults.double(forKey: "volume") == 0.42)
        }
        defaults.set("unknown-future-mode", forKey: AppearanceMode.storageKey)
        let invalid = AppStorage(wrappedValue: AppearanceMode.system, AppearanceMode.storageKey, store: defaults)
        #expect(invalid.wrappedValue == .system)
    }

    private func resolved(_ color: NSColor, appearance: NSAppearance) throws -> NSColor {
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
        return try #require(result)
    }

    private func luminance(_ color: NSColor) -> Double {
        func linear(_ c: CGFloat) -> Double {
            let value = Double(c)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }

    @Test func accentsHaveContrastOnNativeLightAndDarkSurfaces() throws {
        for (scheme, name) in [(ColorScheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            let appearance = try #require(NSAppearance(named: name))
            let accent = try resolved(NSColor(ThemePalette.accent(for: scheme)), appearance: appearance)
            let success = try resolved(NSColor(ThemePalette.success(for: scheme)), appearance: appearance)
            for background in [NSColor.windowBackgroundColor, .controlBackgroundColor, .textBackgroundColor] {
                let surface = try resolved(background, appearance: appearance)
                func contrast(_ foreground: NSColor) -> Double {
                    let a = luminance(foreground), b = luminance(surface)
                    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
                }
                #expect(contrast(accent) >= 4.5, "Small highlighted text must contrast with the native surface")
                #expect(contrast(success) >= 3, "The completion icon must contrast with the native surface")
            }
        }
    }

    @Test func darkModeRetainsOriginalBrandAndSuccessColors() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        #expect(try resolved(NSColor(ThemePalette.accent(for: .dark)), appearance: dark)
                == resolved(NSColor(Color.pink), appearance: dark))
        #expect(try resolved(NSColor(ThemePalette.success(for: .dark)), appearance: dark)
                == resolved(NSColor(Color.green), appearance: dark))
    }
}
