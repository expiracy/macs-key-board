import XCTest
@testable import MacsKeyBoredCore

final class FlagBitsTests: XCTestCase {
    // CGEventFlags values, written out so the test doesn't lean on the code under test.
    private let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000
    private let capsLock: UInt64 = 0x10000, numericPad: UInt64 = 0x200000
    private let leftControl: UInt64 = 0x1, leftCommand: UInt64 = 0x8, rightCommand: UInt64 = 0x10, rightControl: UInt64 = 0x2000
    private let leftShift: UInt64 = 0x2, leftOption: UInt64 = 0x20

    func testReadsTheFourModifiers() {
        XCTAssertEqual(FlagBits.modifiers(command | shift | capsLock), [.command, .shift])
        XCTAssertEqual(FlagBits.modifiers(control | option), [.control, .option])
        XCTAssertEqual(FlagBits.modifiers(capsLock | numericPad), [])
    }

    func testSwappingMovesTheSideBitsAcross() {
        let raw = command | rightCommand | shift | leftShift | numericPad
        let rewritten = FlagBits.rewrite(raw, to: [.control, .shift], swappedCommandControl: true)
        XCTAssertEqual(rewritten, control | rightControl | shift | leftShift | numericPad)
    }

    func testSwappingControlGivesTheLeftCommandKey() {
        let rewritten = FlagBits.rewrite(control | leftControl, to: .command, swappedCommandControl: true)
        XCTAssertEqual(rewritten, command | leftCommand)
    }

    func testAddedModifiersComeFromTheLeftKeysAndOtherBitsSurvive() {
        let rewritten = FlagBits.rewrite(capsLock, to: .hyper, swappedCommandControl: false)
        XCTAssertEqual(rewritten, capsLock | control | leftControl | option | leftOption | shift | leftShift
                       | command | leftCommand)
    }

    func testRemovedModifiersLoseBothSides() {
        let rewritten = FlagBits.rewrite(command | leftCommand | rightCommand | shift | leftShift, to: .shift,
                                         swappedCommandControl: false)
        XCTAssertEqual(rewritten, shift | leftShift)
    }
}
