import CoreGraphics
import Testing
@testable import AXorcist

@Suite("Click event generation")
struct ClickEventGenerationTests {
    @Test("Single click uses clickState=1")
    @MainActor
    func singleClickUsesClickStateOne() throws {
        let pairs = try Element.buildClickEventPairs(
            at: CGPoint(x: 10, y: 20),
            button: .left,
            clickCount: 1)

        #expect(pairs.count == 1)
        #expect(pairs[0].down.type == .leftMouseDown)
        #expect(pairs[0].up.type == .leftMouseUp)
        #expect(pairs[0].down.getIntegerValueField(.mouseEventClickState) == 1)
        #expect(pairs[0].up.getIntegerValueField(.mouseEventClickState) == 1)
    }

    @Test("Double click emits clickState sequence 1 then 2")
    @MainActor
    func doubleClickUsesSequentialClickStates() throws {
        let pairs = try Element.buildClickEventPairs(
            at: CGPoint(x: 10, y: 20),
            button: .left,
            clickCount: 2)

        #expect(pairs.count == 2)
        #expect(pairs[0].down.type == .leftMouseDown)
        #expect(pairs[0].up.type == .leftMouseUp)
        #expect(pairs[0].down.getIntegerValueField(.mouseEventClickState) == 1)
        #expect(pairs[0].up.getIntegerValueField(.mouseEventClickState) == 1)

        #expect(pairs[1].down.type == .leftMouseDown)
        #expect(pairs[1].up.type == .leftMouseUp)
        #expect(pairs[1].down.getIntegerValueField(.mouseEventClickState) == 2)
        #expect(pairs[1].up.getIntegerValueField(.mouseEventClickState) == 2)
    }
}

