import AppKit

// Grandpa Yugong's pose rig: the key poses of every routine, drawn by the pixel art.
//
// Canvas: 100 x 100 units, y grows downward, ground at y = 94, Grandpa faces LEFT (toward
// the mountain). Original design written for this project from the Liezi tale (public domain).

enum Eyes { case open, closed, happy, squeeze }
enum Mouth { case smile, open, yawn, snore }
enum Bird { case perch, chirp, hop, sleep, look }
enum FX { case none, zzz, notes, yawn, sweatFly, sparkle, pant }
enum Clump { case none, onBlade, flying }

struct YPose {
    var hip = CGPoint(x: 57, y: 64)
    var lean: CGFloat = 6            // degrees; + leans forward (toward the left)
    var head: CGFloat = 0            // extra head tilt; + nods forward
    var footF = CGPoint(x: 47, y: 94)
    var footB = CGPoint(x: 66, y: 94)
    var toolTop = CGPoint(x: 54, y: 30)
    var toolAng: CGFloat = 35        // handle direction from its top: 0 = straight down, + = blade toward the left
    var handF: CGPoint? = nil        // nil = holds the shovel (lower grip)
    var handB: CGPoint? = nil        // nil = holds the shovel (top grip)
    var eyes = Eyes.open
    var mouth = Mouth.smile
    var lookBack = false             // turns his face to the magpie behind him
    var sweat = false
    var clump = Clump.none
    var sit = false
    var hatTip: CGFloat = 0
    var jigeOnBack = true
    var bird = Bird.perch
    var fx = FX.none
    var beard: CGFloat = 0           // beard sway, units
    var sq: CGFloat = 1              // squash (<1) and stretch (>1), volume kept

    var toolDir: CGPoint {
        let a = toolAng * .pi / 180
        return CGPoint(x: -sin(a), y: cos(a))
    }
    var gripTop: CGPoint { CGPoint(x: toolTop.x + toolDir.x * 3, y: toolTop.y + toolDir.y * 3) }
    var gripLow: CGPoint { CGPoint(x: toolTop.x + toolDir.x * 19, y: toolTop.y + toolDir.y * 19) }
    var handFront: CGPoint { handF ?? gripLow }
    var handBack: CGPoint { handB ?? gripTop }
}

/// A key pose held for `dur` seconds; the first part of it eases in from the previous key.
struct Key {
    var pose: YPose
    var dur: Double
}

enum YugongRig {
    // MARK: - key poses

    static let stand = YPose()

    // digging, four beats: lift - thrust - pry - toss
    static func dig(depth d: CGFloat, tired: Bool) -> [YPose] {
        var lift = YPose(hip: CGPoint(x: 58, y: 64 + d * 0.3), lean: 6 + d, toolTop: CGPoint(x: 55, y: 30 + d), toolAng: 35)
        var thrust = YPose(hip: CGPoint(x: 56, y: 67 + d), lean: 22 + d, head: 4, footF: CGPoint(x: 44, y: 94),
                           toolTop: CGPoint(x: 52, y: 41 + d), toolAng: 25, eyes: .squeeze, mouth: tired ? .open : .smile)
        thrust.beard = -2; thrust.sq = 1.03
        lift.sq = 0.93                                     // anticipation: crouch before the thrust
        var pry = YPose(hip: CGPoint(x: 58, y: 66 + d), lean: 16 + d, footF: CGPoint(x: 45, y: 94),
                        toolTop: CGPoint(x: 62, y: 50 + d * 0.5), toolAng: 62, clump: .onBlade)
        pry.mouth = tired ? .open : .smile
        var toss = YPose(hip: CGPoint(x: 59, y: 64 + d * 0.4), lean: -6 + d * 0.8, head: -6,
                         toolTop: CGPoint(x: 61, y: 56), toolAng: tired ? 120 : 145, eyes: .happy, clump: .flying)
        toss.beard = 2; toss.sq = 1.07
        if tired {
            lift.eyes = .squeeze; lift.sweat = true; lift.mouth = .open
            toss.eyes = .squeeze; toss.sweat = true; toss.mouth = .open
            pry.sweat = true
        }
        return [lift, thrust, pry, toss]
    }

    static func leanOnShovel(talk: Bool) -> YPose {
        var p = YPose(hip: CGPoint(x: 58, y: 64), lean: 8, toolTop: CGPoint(x: 41, y: 50), toolAng: -6,
                      handF: CGPoint(x: 40, y: 51), handB: CGPoint(x: 43, y: 54))
        if talk { p.lookBack = true; p.mouth = .open; p.bird = .chirp; p.fx = .notes; p.head = -4 }
        else { p.eyes = .happy; p.bird = .look }
        return p
    }

    static func wipeSweat(_ phase: Int) -> YPose {
        var p = YPose(hip: CGPoint(x: 58, y: 64), lean: 4, head: -6, toolTop: CGPoint(x: 41, y: 50), toolAng: -6,
                      handB: CGPoint(x: 43, y: 52), eyes: .squeeze, mouth: .open, sweat: phase == 0)
        // forearm sweeps across the brow
        p.handF = phase == 0 ? CGPoint(x: 35, y: 27) : CGPoint(x: 41, y: 21)
        if phase == 1 { p.fx = .sweatFly; p.eyes = .closed; p.mouth = .smile }
        return p
    }

    static func backStretch() -> YPose {
        YPose(hip: CGPoint(x: 58, y: 64), lean: -15, head: -10, toolTop: CGPoint(x: 41, y: 50), toolAng: -6,
              handF: CGPoint(x: 41, y: 51), handB: CGPoint(x: 67, y: 60), eyes: .squeeze, mouth: .open, fx: .pant)
    }

    static func yawn() -> YPose {
        YPose(hip: CGPoint(x: 58, y: 64), lean: -4, head: -12, toolTop: CGPoint(x: 41, y: 50), toolAng: -6,
              handF: CGPoint(x: 41, y: 33), handB: CGPoint(x: 43, y: 53), eyes: .closed, mouth: .yawn, fx: .yawn)
    }

    static func rest(_ breathIn: Bool) -> YPose {
        var p = YPose(hip: CGPoint(x: 52, y: 85), lean: -20, head: 16,
                      footF: CGPoint(x: 23, y: 93), footB: CGPoint(x: 30, y: 94),
                      toolTop: CGPoint(x: 15, y: 52), toolAng: -4,
                      handF: CGPoint(x: 44, y: 75), handB: CGPoint(x: 48, y: 77),
                      eyes: .closed, mouth: .snore, sit: true, hatTip: 1, jigeOnBack: false, bird: .sleep, fx: .zzz)
        if breathIn { p.hip.y -= 0.8; p.lean -= 2; p.mouth = .smile }
        return p
    }

    static func morning(_ beat: Int) -> YPose {
        var p = YPose(hip: CGPoint(x: 57, y: 63), lean: -10, head: -14, toolTop: CGPoint(x: 26, y: 50), toolAng: -3,
                      handF: CGPoint(x: 33, y: 33), handB: CGPoint(x: 81, y: 31), eyes: .closed, mouth: .yawn,
                      jigeOnBack: false, bird: .hop, fx: .sparkle)
        switch beat {
        case 0: p.sq = 1.08                                                 // big stretch
        case 1: p.lean = 2; p.head = 0; p.hip.y = 64                         // hands on hips, beaming
                p.handF = CGPoint(x: 52, y: 62); p.handB = CGPoint(x: 64, y: 62); p.eyes = .happy; p.mouth = .open
                p.bird = .chirp; p.fx = .notes
        default: p.lean = 14; p.head = 4; p.hip.y = 66                       // reaches for the shovel
                p.handF = CGPoint(x: 30, y: 53); p.handB = CGPoint(x: 34, y: 56); p.eyes = .open; p.mouth = .smile
                p.bird = .perch; p.fx = .none
        }
        return p
    }

    // MARK: - routines per state

    static func keys(_ s: PetState, night: Bool, tempo: Tempo = .working) -> [Key] {
        let working = s == .lively || s == .steady || s == .straining
        if working && tempo == .idle {
            // no tokens flowing: he leans on the shovel and chats with the magpie (yawns at night)
            return night ? [Key(pose: yawn(), dur: 1.6), Key(pose: leanOnShovel(talk: false), dur: 2.4)]
                         : [Key(pose: leanOnShovel(talk: true), dur: 1.4), Key(pose: leanOnShovel(talk: false), dur: 2.0)]
        }
        if working && tempo == .sweating {
            return keys(s, night: night).map { var k = $0; k.pose.sweat = true; return k }
        }
        func digKeys(_ beats: [YPose], _ d: [Double]) -> [Key] { zip(beats, d).map { Key(pose: $0, dur: $1) } }
        switch s {
        case .lively:
            let d = dig(depth: 0, tired: false), t = [0.32, 0.28, 0.32, 0.48]
            let habit: [Key] = night
                ? [Key(pose: yawn(), dur: 1.6), Key(pose: stand, dur: 0.4)]
                : [Key(pose: leanOnShovel(talk: true), dur: 1.4), Key(pose: leanOnShovel(talk: false), dur: 0.8)]
            return digKeys(d, t) + digKeys(d, t) + digKeys(d, t) + habit
        case .steady:
            let d = dig(depth: 3, tired: false), t = [0.42, 0.36, 0.42, 0.6]
            let habit: [Key] = night
                ? [Key(pose: yawn(), dur: 1.6)]
                : [Key(pose: wipeSweat(0), dur: 0.7), Key(pose: wipeSweat(1), dur: 0.7),
                   Key(pose: backStretch(), dur: 1.2)]
            return digKeys(d, t) + digKeys(d, t) + habit
        case .straining:
            let d = dig(depth: 6, tired: true), t = [0.6, 0.5, 0.7, 0.8]
            var pant = leanOnShovel(talk: false); pant.eyes = .squeeze; pant.mouth = .open; pant.sweat = true; pant.fx = .pant; pant.bird = .perch
            var pant2 = pant; pant2.hip.y += 1; pant2.lean += 3
            return digKeys(d, t) + [Key(pose: pant, dur: 0.6), Key(pose: pant2, dur: 0.6), Key(pose: pant, dur: 0.6),
                                    Key(pose: wipeSweat(0), dur: 0.7), Key(pose: wipeSweat(1), dur: 0.7)]
        case .resting:
            return [Key(pose: rest(true), dur: 2.0), Key(pose: rest(false), dur: 2.0)]
        case .morning:
            return [Key(pose: morning(0), dur: 1.5), Key(pose: morning(1), dur: 1.1), Key(pose: morning(2), dur: 0.8)]
        }
    }

    static func period(_ s: PetState, night: Bool, tempo: Tempo = .working) -> Double { keys(s, night: night, tempo: tempo).reduce(0) { $0 + $1.dur } }

    /// The pose at time `t`, snapping from key to key (pixel art has no in-betweens).
    /// Also returns progress 0...1 through the current key, for effects that travel.
    static func pose(_ s: PetState, t: Double, night: Bool, tempo: Tempo = .working) -> (YPose, CGFloat) {
        let ks = keys(s, night: night, tempo: tempo)
        let per = ks.reduce(0) { $0 + $1.dur }
        var p = t.truncatingRemainder(dividingBy: per)
        if p < 0 { p += per }
        for (i, k) in ks.enumerated() {
            if p < k.dur || i == ks.count - 1 {
                let k01 = CGFloat(min(1, max(0, p / k.dur)))
                return (k.pose, k01)
            }
            p -= k.dur
        }
        return (stand, 0)
    }

    /// Same signature = same picture (used to skip menu-bar redraws). Travelling effects are
    /// quantized the same way the renderers quantize them.
    static func signature(_ s: PetState, t: Double, night: Bool, tempo: Tempo = .working) -> String {
        let (p, k) = pose(s, t: t, night: night, tempo: tempo)
        let q = Int(k * 3)
        return String(format: "%.1f %.1f %.1f %.1f %.1f %.1f %.1f ", p.hip.x, p.hip.y, p.lean, p.toolTop.x, p.toolAng,
                      p.handFront.y, p.handBack.y) + "\(p.sweat) \(p.eyes) \(p.mouth) \(p.fx) \(p.bird) \(p.clump) \(q)"
    }
}
