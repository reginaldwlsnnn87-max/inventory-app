import XCTest
@testable import inventory_app

final class TVConnectionStateMachineTests: XCTestCase {
    func testStateMachineTransitionOrderForHappyPath() {
        var machine = TVConnectionStateMachine()
        let device = TVDevice.manualLG(ip: "192.168.1.47")

        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.transition(.beginScan), .scanning)
        XCTAssertEqual(machine.transition(.foundDevices(1)), .discovered(count: 1))
        XCTAssertEqual(machine.transition(.beginPairing(device)), .pairing(device: device))
        XCTAssertEqual(machine.transition(.didConnect(device)), .connected(device: device))
    }

    func testStateMachineCanRecoverFromFailure() {
        var machine = TVConnectionStateMachine()
        let device = TVDevice.manualLG(ip: "192.168.1.48")

        XCTAssertEqual(machine.transition(.beginScan), .scanning)
        XCTAssertEqual(machine.transition(.fail("Local Network denied")), .failed(message: "Local Network denied"))
        XCTAssertEqual(machine.transition(.beginReconnect(device)), .reconnecting(device: device))
    }
}

