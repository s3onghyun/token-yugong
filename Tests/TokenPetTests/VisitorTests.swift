import Foundation
import Testing
@testable import TokenPetAssets
@testable import TokenPet

// LOGIC.md "Visitors": when the wife, Zhisou and Kua'e's sons appear.

@Suite struct VisitorRules {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snap(five: Double = 30, weekResets: TimeInterval = 3 * 86400) -> Snapshot {
        Logic.evaluate(main: Reading(five: Meter(pct: five, resetsAt: now.addingTimeInterval(3600)),
                                     week: Meter(pct: 40, resetsAt: now.addingTimeInterval(weekResets)), at: now), now: now)
    }

    @Test func zhisouComesWhenTheLimitIsUsedUp() {
        #expect(Visitors.who(snap(five: 100), changedAt: nil, carried: 0.1, mountain: 0, now: now) == .zhisou)
        #expect(Visitors.who(snap(five: 99), changedAt: nil, carried: 0.1, mountain: 0, now: now) == nil)
        // he outranks the wife
        #expect(Visitors.who(snap(five: 100), changedAt: now, carried: 0.1, mountain: 0, now: now) == .zhisou)
    }

    @Test func nobodyComesWhileHeDoesNotKnow() {
        #expect(Visitors.who(Snapshot(), changedAt: now, carried: 0.9, mountain: 0, now: now) == nil)
    }

    @Test func theWifeAsksForTenMinutesAfterAChange() {
        let s = snap()
        #expect(Visitors.who(s, changedAt: now.addingTimeInterval(-60), carried: 0.2, mountain: 0, now: now) == .wifeDoubting)
        #expect(Visitors.who(s, changedAt: now.addingTimeInterval(-601), carried: 0.2, mountain: 0, now: now) == nil)
        #expect(Visitors.who(s, changedAt: now.addingTimeInterval(60), carried: 0.2, mountain: 0, now: now) == nil)   // a clock moved back
        #expect(Visitors.who(s, changedAt: nil, carried: 0.2, mountain: 0, now: now) == nil)
    }

    @Test func theWifeComesForTheFirstSixHoursOfAWeek() {
        let fresh = snap(weekResets: 7 * 86400 - 3600)        // the week began an hour ago
        #expect(fresh.weekStart == now.addingTimeInterval(-3600))
        #expect(Visitors.who(fresh, changedAt: nil, carried: 0.2, mountain: 0, now: now) == .wifeDoubting)
        let later = snap(weekResets: 7 * 86400 - 6 * 3600 - 1)
        #expect(Visitors.who(later, changedAt: nil, carried: 0.2, mountain: 0, now: now) == nil)
        let rolled = snap(weekResets: -1800)                  // the reset passed and the tool has not reported since
        #expect(rolled.weekStart == now.addingTimeInterval(-1800))
        #expect(Visitors.who(rolled, changedAt: nil, carried: 0.2, mountain: 0, now: now) == .wifeDoubting)
    }

    @Test func theWifeCheersOnceHalfTheMountainIsGone() {
        let s = snap()
        #expect(Visitors.who(s, changedAt: now, carried: 0.49, mountain: 0, now: now) == .wifeDoubting)
        #expect(Visitors.who(s, changedAt: now, carried: 0.5, mountain: 0, now: now) == .wifeCheering)
        #expect(Visitors.who(s, changedAt: now, carried: 0, mountain: 1, now: now) == .wifeCheering)   // after the first mountain she believes
    }

    @Test func thePlanChangesWithTheFamilyOrTheWindows() {
        let s = snap()
        let p = Visitors.plan(.standard, s)
        #expect(p != nil)
        #expect(Visitors.plan(.standard.assigning(.gemini, to: .son), s) != p)
        var weeklyOnly = s; weeklyOnly.five = nil
        #expect(Visitors.plan(.standard, weeklyOnly) != p)
        #expect(Visitors.plan(.standard, Snapshot()) == nil)   // no reading is not a change of plan
    }

    @Test func everyVisitorHasBothLines() {
        for v in Visitor.allCases {
            let (a, b) = Visitors.lines(v)
            #expect(!a.isEmpty && !b.isEmpty)
        }
    }
}

@Suite struct VisitorArt {
    @Test func headsAreRectangular() {
        for rows in [VisitorHeads.wife, VisitorHeads.zhisou, VisitorHeads.giant] {
            #expect(Set(rows.map(\.count)).count == 1)
        }
    }

    @Test func routines() {
        #expect(YugongArt.wifePose(0.2, cheering: false) == .hips && YugongArt.wifePose(1.2, cheering: false) == .ask)
        #expect(YugongArt.wifePose(0.1, cheering: true) == .cheer && YugongArt.wifePose(0.5, cheering: true) == .clap)
        #expect(YugongArt.zhisouPose(0.3) == .laugh && YugongArt.zhisouPose(1.0) == .point && YugongArt.zhisouPose(-0.3) == .point)
    }

    @Test func kuaeSonsRiseThenCarryTheMountainOff() {
        let w = 97
        let start = YugongArt.cutsceneMotion(0, width: w), up = YugongArt.cutsceneMotion(0.4, width: w), end = YugongArt.cutsceneMotion(1, width: w)
        #expect(start.lift == 0 && start.dx == 0 && start.pose == .lift)
        #expect(up.lift == 31 && up.dx == 0 && up.pose == .lift)
        #expect(end.lift == 31 && end.dx <= -CGFloat(w) * 0.8 + 1)       // both sons and the mountain are off the left edge
        let mid = YugongArt.cutsceneMotion(0.7, width: w)
        #expect(mid.dx < 0 && mid.dx > end.dx && mid.pose != .lift)
    }

    @Test func layersDraw() {
        for v in Visitor.allCases { #expect(YugongArt.visitorLayer(v, t: 0.3).0 != nil) }
        for p in GiantPose.allCases { #expect(YugongArt.giantLayer(p, brother: 1) != nil) }
    }
}
