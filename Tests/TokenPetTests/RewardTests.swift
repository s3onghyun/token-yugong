import AppKit
import Testing
@testable import TokenPetAssets
@testable import TokenPet

// LOGIC.md "Title rewards": one reward per title, kept; five of them reach the menu bar.

@Suite struct TitleRewards {
    /// The image's pixels, so two pictures can be compared exactly.
    func pixels(_ img: NSImage) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width) * 2, pixelsHigh: Int(img.size.height) * 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    func bar(_ titles: Int) -> Data {
        pixels(TokenPetAssets.figure(.lively, t: 0.9, carrier: 0.5, night: false, size: 20, menuBar: true, titles: titles))
    }

    func scene(_ titles: Int, props: Bool = true) -> Data {
        var i = SceneInfo(state: .lively, carrier: 0.5, mountainLeft: 0.8, grandson: 0.3, night: false)
        i.titles = titles; i.props = props
        return pixels(TokenPetAssets.scene(i, t: 0.9, size: CGSize(width: 292, height: 176)))
    }

    @Test func everyTitleAddsSomethingToTheScene() {
        for n in 1...10 { #expect(scene(n) != scene(n - 1), "title \(n) changed nothing in the scene") }
    }

    @Test func onlyFiveTitlesChangeTheMenuBar() {
        let changes = (1...10).filter { bar($0) != bar($0 - 1) }
        #expect(changes == [1, 2, 3, 8, 10])          // iron shovel, tassel, pickaxe, banner, golden shovel
        #expect(bar(1) == bar(Titles.rank(100_000) + 1))
    }

    @Test func hidingPropsKeepsOnlyGrandpasGear() {
        let changes = (1...10).filter { scene($0, props: false) != scene($0 - 1, props: false) }
        #expect(changes == [1, 2, 3, 10])             // the shovel, the tassel, the pickaxe, the golden blade
        #expect(scene(10, props: false) != scene(10))
    }

    @Test func propsStepAroundTheFamily() {
        let w = 97
        func clearOf(_ info: SceneInfo) -> Bool {
            let l = TitleWorld.layout(info, w: w), taken = TitleWorld.occupied(info, w: w)
            let basket = TitleWorld.cover(l.baskets, l.pair ? 24 : 12, taken + [l.house..<(l.house + 13)])   // nor on the house
            return basket == 0 && TitleWorld.cover(l.house, 13, taken) == 0
        }
        var alone = SceneInfo(state: .lively, carrier: 0.5, mountainLeft: 1, grandson: nil, night: false)
        #expect(clearOf(alone) && TitleWorld.layout(alone, w: w).pair)
        alone.grandson = 0.3                                          // the default family: the house moves to the left
        #expect(clearOf(alone) && TitleWorld.layout(alone, w: w).house < 20)
        alone.son = 0.4                                               // no room for both baskets: one, still in the clear
        #expect(clearOf(alone) && !TitleWorld.layout(alone, w: w).pair)
    }
}

@Suite struct TheFinale {
    func store() -> UserDefaults {
        let name = "tokenpet-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func playsOnceAtTheTopTitleAndSurvivesARestart() {
        let d = store()
        var b = TitleBook.load(d)
        #expect(!b.finaleDue(2_999_999_999))
        #expect(b.finaleDue(3_000_000_000))
        b.finaleSeen = true; b.save()
        #expect(!b.finaleDue(5e9))
        #expect(!TitleBook.load(d).finaleDue(5e9))                    // restarted: still watched
        var again = TitleBook.load(d)                                 // observing more titles does not bring it back
        _ = again.observe(TitleInputs(lifetime: 4e9, snap: Snapshot(), now: Date()))
        #expect(!TitleBook.load(d).finaleDue(4e9))
    }
}
