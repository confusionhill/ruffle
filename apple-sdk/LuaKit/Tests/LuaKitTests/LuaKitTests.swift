import XCTest
@testable import LuaKit

@MainActor
final class LuaKitTests: XCTestCase {
    func testBasicExecutionAndPrintCapture() {
        let engine = LuaEngine()
        engine.run("""
        local sum = 0
        for i = 1, 5 do
            if i % 2 == 1 then
                sum = sum + i
            end
        end
        print("sum=" .. sum)
        """)

        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.lastError)
        XCTAssertEqual(engine.consoleLogs.last?.message, "sum=9")
    }

    func testFunctionRegistrationAndTableMarshaling() {
        let engine = LuaEngine()
        engine.registerFunction(table: "player", name: "stats") { _ in
            LuaValue.from(any: ["hp": 1200, "name": "Artix", "alive": true])
        }
        engine.registerFunction(table: "combat", name: "echoArgs") { args in
            let first = args.first?.stringValue ?? "none"
            let second = args.dropFirst().first?.intValue ?? -1
            return .string("\(first):\(second)")
        }

        engine.run("""
        local s = player.stats()
        local res = combat.echoArgs(s.name, s.hp)
        print(res, tostring(s.alive))
        """)

        XCTAssertNil(engine.lastError)
        XCTAssertEqual(engine.consoleLogs.last?.message, "Artix:1200\ttrue")
    }

    func testCoroutineSleepAndResume() {
        let engine = LuaEngine()
        let exp = expectation(description: "Lua coroutine finishes after sleep")

        engine.run("""
        print("start")
        sleep(30)
        print("after_sleep")
        """)

        XCTAssertTrue(engine.isRunning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertFalse(engine.isRunning)
            XCTAssertNil(engine.lastError)
            XCTAssertEqual(engine.consoleLogs.map(\.message), ["start", "after_sleep"])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testStopCancelsYieldedCoroutine() {
        let engine = LuaEngine()
        let exp = expectation(description: "Stopped coroutine does not continue")

        engine.run("""
        print("tick1")
        sleep(200)
        print("tick2")
        """)

        XCTAssertTrue(engine.isRunning)
        engine.stop()
        XCTAssertFalse(engine.isRunning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(engine.consoleLogs.map(\.message), ["tick1", "Script stopped."])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testSyntaxErrorReportsLineNumber() {
        let engine = LuaEngine()
        engine.run("""
        local x = 1
        local y = (
        """, name: "bad.lua")

        XCTAssertFalse(engine.isRunning)
        XCTAssertNotNil(engine.lastError)
        XCTAssertTrue(engine.lastError?.contains("bad.lua") == true)
    }
}

