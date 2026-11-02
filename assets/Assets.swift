import AppKit

/// What the character is doing. Driven by the usage model; drawn by the character art.
///   lively / steady / straining - working pace (tokens per hour vs time left before reset)
///   resting  - the 5-hour carrier is full (limit reached); he sits down until the wake time
///   morning  - the window just reset; he stretches and picks the shovel back up
public enum PetState: String, CaseIterable {
    case lively, steady, straining, resting, morning

    /// Older flag names from the first prototype still work.
    public init?(flag: String) {
        switch flag {
        case "full": self = .straining
        case "asleep": self = .resting
        case "stretch": self = .morning
        default: self.init(rawValue: flag)
        }
    }
}

/// How fast tokens are flowing right now (RunCat-style live pace). The caller sets the speed
/// of the clock it passes as `t`; this only picks the routine: idle = leaning on the shovel and
/// chatting, working = digging, sweating = digging with sweat flying.
public enum Tempo: String, CaseIterable {
    case idle, working, sweating
}

/// The two finished art styles of the same poses.
public enum ArtStyle: String, CaseIterable {
    case pixel, ink
}

/// Everything the popover scene needs besides the clock.
public struct SceneInfo {
    public var state: PetState
    public var carrier: Double           // 0...1, Claude 5-hour (or weekly) usage = earth in Grandpa's carrier
    public var mountainLeft: Double      // 1 = untouched mountain, 0 = all carried away
    public var grandson: Double?         // Codex usage 0...1; nil hides the grandson
    public var night: Bool
    public var cutscene: Double?         // 0...1 progress of the milestone cutscene placeholder; nil = none
    public var tempo: Tempo = .working

    public init(state: PetState, carrier: Double, mountainLeft: Double, grandson: Double?, night: Bool, cutscene: Double? = nil) {
        self.state = state; self.carrier = carrier; self.mountainLeft = mountainLeft
        self.grandson = grandson; self.night = night; self.cutscene = cutscene
    }
}

/// Entry points into the separately licensed character assets.
public enum TokenPetAssets {
    /// The character alone, feet on the bottom edge, inside a `size` square.
    public static func figure(_ style: ArtStyle, _ state: PetState, t: Double, carrier: Double, night: Bool,
                              size: CGFloat, menuBar: Bool, tempo: Tempo = .working) -> NSImage {
        YugongArt.figure(style, state, t: t, carrier: carrier, night: night, size: size, menuBar: menuBar, tempo: tempo)
    }

    /// The whole popover scene: sky, the mountain, Grandpa, the magpie and the grandson.
    public static func scene(_ style: ArtStyle, _ info: SceneInfo, t: Double, size: CGSize) -> NSImage {
        YugongArt.scene(style, info, t: t, size: size)
    }

    /// A pose signature, so a caller can tell when two moments draw the same picture.
    public static func signature(_ style: ArtStyle, _ state: PetState, t: Double, night: Bool, tempo: Tempo = .working) -> String {
        YugongRig.signature(state, t: t, night: night, stepped: style == .pixel, tempo: tempo)
    }

    /// The app icon (pixel style) at `size` points.
    public static func appIcon(size: CGFloat, t: Double = iconMoment) -> NSImage { YugongArt.appIcon(size: size, t: t) }
    public static let iconMoment = 0.0

    /// Length of one seamless loop of the character's routine in this state.
    public static func period(_ state: PetState, night: Bool, tempo: Tempo = .working) -> Double { YugongRig.period(state, night: night, tempo: tempo) }
}
