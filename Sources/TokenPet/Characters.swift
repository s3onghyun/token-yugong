import AppKit
import TokenPetAssets

/// The two finished art styles of Grandpa Yugong. The art itself lives in the separately
/// licensed assets module; this is the app-side glue.
enum CharacterStyle: String, CaseIterable, Identifiable {
    case pixel, ink
    var id: String { rawValue }
    var art: ArtStyle { self == .pixel ? .pixel : .ink }

    var name: String { L.t("Grandpa Yugong", "우공 할아버지") }
    var styleLabel: String { self == .pixel ? L.t("Pixel", "픽셀") : L.t("Ink", "수묵") }
    var crisp: Bool { self == .pixel }

    static func validateAssets() -> String? { nil }

    /// The character alone (menu bar and picker), at time `t`.
    func image(_ state: PetState, t: TimeInterval, size: CGFloat, menuBar: Bool = false, carrier: Double = 0.4, night: Bool = false) -> NSImage {
        TokenPetAssets.figure(art, state, t: Motion.reduce ? 0 : t, carrier: carrier, night: night, size: size, menuBar: menuBar)
    }

    /// The popover scene.
    func scene(_ info: SceneInfo, t: TimeInterval, size: CGSize) -> NSImage {
        TokenPetAssets.scene(art, info, t: Motion.reduce ? 0 : t, size: size)
    }
}

enum Motion {
    /// Respect "Reduce motion": the character holds one pose.
    static var reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    static func period(_ s: PetState, night: Bool) -> Double { TokenPetAssets.period(s, night: night) }
}
