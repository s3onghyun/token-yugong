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

/// Someone from the tale who drops by (LOGIC.md "Visitors"): the wife doubting or cheering, or Zhisou mocking.
public enum Visitor: String, CaseIterable {
    case wifeDoubting, wifeCheering, zhisou
}

/// Everything the popover scene needs besides the clock.
public struct SceneInfo {
    public var state: PetState
    public var carrier: Double           // 0...1, Claude 5-hour (or weekly) usage = earth in Grandpa's carrier
    public var mountainLeft: Double      // 1 = untouched mountain, 0 = all carried away
    public var grandson: Double?         // the grandson's AI, 0...1; nil hides him
    public var son: Double? = nil        // the son's AI (his heap of stone); nil hides him
    public var boy: Double? = nil        // the neighbour's boy's AI (his basket); nil hides him
    public var night: Bool
    public var cutscene: Double?         // 0...1 progress of the milestone cutscene (Kua'e's sons carry the mountain off); nil = none
    public var visitor: Visitor? = nil   // someone from the tale standing at the left; nil = nobody
    public var tempo: Tempo = .working
    /// Titles earned, 0...10: each adds one reward to the scene (LOGIC.md "Title rewards"). 1 = the classic look.
    public var titles = 1
    /// false hides the background rewards (sky, horizon, ground); the gear on Grandpa stays.
    public var props = true
    /// The cutscene is the one-time #10 finale (both mountains carried off) instead of a mountain milestone.
    public var finale = false
    /// A title just earned (1...10): its reward glints during the celebration.
    public var sparkle: Int? = nil

    public init(state: PetState, carrier: Double, mountainLeft: Double, grandson: Double?, night: Bool, cutscene: Double? = nil) {
        self.state = state; self.carrier = carrier; self.mountainLeft = mountainLeft
        self.grandson = grandson; self.night = night; self.cutscene = cutscene
    }
}

/// Entry points into the separately licensed character assets.
public enum TokenPetAssets {
    /// The character alone, feet on the bottom edge, inside a `size` square.
    public static func figure(_ state: PetState, t: Double, carrier: Double, night: Bool,
                              size: CGFloat, menuBar: Bool, tempo: Tempo = .working, titles: Int = 1) -> NSImage {
        YugongArt.figure(state, t: t, carrier: carrier, night: night, size: size, menuBar: menuBar, tempo: tempo, titles: titles)
    }

    /// The whole popover scene: sky, the mountain, Grandpa, the magpie and the grandson.
    public static func scene(_ info: SceneInfo, t: Double, size: CGSize) -> NSImage {
        YugongArt.scene(info, t: t, size: size)
    }

    /// A pose signature, so a caller can tell when two moments draw the same picture.
    public static func signature(_ state: PetState, t: Double, night: Bool, tempo: Tempo = .working) -> String {
        YugongRig.signature(state, t: t, night: night, tempo: tempo)
    }

    /// The app icon at `size` points.
    public static func appIcon(size: CGFloat, t: Double = iconMoment) -> NSImage { YugongArt.appIcon(size: size, t: t) }
    public static let iconMoment = 0.0

    /// Length of one seamless loop of the character's routine in this state.
    public static func period(_ state: PetState, night: Bool, tempo: Tempo = .working) -> Double { YugongRig.period(state, night: night, tempo: tempo) }
}
