import AppKit
import TokenPetAssets

/// Grandpa Yugong in pixel art. The art itself lives in the separately licensed assets
/// module; this is the app-side glue.
enum Yugong {
    /// The character alone (menu bar and guide), at time `t`.
    static func image(_ state: PetState, t: TimeInterval, size: CGFloat, menuBar: Bool = false, carrier: Double = 0.4, night: Bool = false, tempo: Tempo = .working) -> NSImage {
        TokenPetAssets.figure(state, t: Motion.reduce ? 0 : t, carrier: carrier, night: night, size: size, menuBar: menuBar, tempo: tempo)
    }

    /// The popover scene.
    static func scene(_ info: SceneInfo, t: TimeInterval, size: CGSize) -> NSImage {
        TokenPetAssets.scene(info, t: Motion.reduce ? 0 : t, size: size)
    }
}

enum Motion {
    /// Respect "Reduce motion": the character holds one pose.
    static var reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    static func period(_ s: PetState, night: Bool, tempo: Tempo = .working) -> Double { TokenPetAssets.period(s, night: night, tempo: tempo) }
}
