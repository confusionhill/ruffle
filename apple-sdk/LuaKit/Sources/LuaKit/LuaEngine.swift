import Foundation
import Combine
import CLua

public enum LuaValue: Equatable {
    case `nil`
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([LuaValue])
    case table([String: LuaValue])

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .nil: return false
        default: return true
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var arrayValue: [LuaValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public var tableValue: [String: LuaValue]? {
        if case .table(let dict) = self { return dict }
        return nil
    }

    public static func from(any value: Any?) -> LuaValue {
        guard let value = value, !(value is NSNull) else { return .nil }
        if let b = value as? Bool { return .bool(b) }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            if floor(n.doubleValue) == n.doubleValue && abs(n.doubleValue) <= Double(Int.max) {
                return .int(n.intValue)
            }
            return .double(n.doubleValue)
        }
        if let i = value as? Int { return .int(i) }
        if let d = value as? Double { return .double(d) }
        if let s = value as? String { return .string(s) }
        if let arr = value as? [Any] { return .array(arr.map { LuaValue.from(any: $0) }) }
        if let dict = value as? [String: Any] {
            var mapped: [String: LuaValue] = [:]
            for (k, v) in dict {
                mapped[k] = LuaValue.from(any: v)
            }
            return .table(mapped)
        }
        return .string("\(value)")
    }
}

public struct ScriptLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: String
    public let message: String
    public let isError: Bool
}

private final class CallbackBox {
    let handler: ([LuaValue]) -> LuaValue
    init(_ handler: @escaping ([LuaValue]) -> LuaValue) {
        self.handler = handler
    }
}

private final class EngineRefBox {
    weak var engine: LuaEngine?
    init(_ engine: LuaEngine) {
        self.engine = engine
    }
}

@MainActor
public final class LuaEngine: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var statusText = "Idle"
    @Published public private(set) var consoleLogs: [ScriptLogEntry] = []
    @Published public private(set) var lastError: String?

    private var L: OpaquePointer?
    private var activeThread: OpaquePointer?
    private var threadRef: Int32 = LUA_NOREF
    private var resumeTimer: Timer?
    private var stopRequested = false

    private var callbackBoxes: [CallbackBox] = []
    private var selfBox: EngineRefBox?

    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public init() {
        resetState()
    }

    deinit {
        resumeTimer?.invalidate()
        if let state = L {
            lua_close(state)
        }
    }

    public func resetState() {
        stop()
        callbackBoxes.removeAll()
        if let state = L {
            lua_close(state)
            L = nil
        }

        guard let state = luaL_newstate() else { return }
        L = state
        luaL_openlibs(state)
        applySandbox(state)

        let box = EngineRefBox(self)
        selfBox = box
        let ptr = Unmanaged.passUnretained(box).toOpaque()

        // Override print(...)
        lua_pushlightuserdata(state, ptr)
        lua_pushcclosure(state, { co -> Int32 in
            guard let co = co else { return 0 }
            let rawPtr = lua_touserdata(co, clua_upvalueindex(1))
            guard let rawPtr = rawPtr else { return 0 }
            let box = Unmanaged<EngineRefBox>.fromOpaque(rawPtr).takeUnretainedValue()

            let argc = lua_gettop(co)
            var parts: [String] = []
            for i in 1...max(1, argc) where argc > 0 {
                if let cStr = luaL_tolstring(co, i, nil) {
                    parts.append(String(cString: cStr))
                }
                clua_pop(co, 1)
            }
            let msg = parts.joined(separator: "\t")
            MainActor.assumeIsolated {
                box.engine?.appendLog(msg, isError: false)
            }
            return 0
        }, 1)
        lua_setglobal(state, "print")

        // Built-in yielding sleep(ms)
        lua_pushcclosure(state, { co -> Int32 in
            guard let co = co else { return 0 }
            let ms = max(1.0, lua_tonumberx(co, 1, nil))
            lua_pushnumber(co, ms)
            return clua_yield(co, 1)
        }, 0)
        lua_setglobal(state, "sleep")
    }

    private func applySandbox(_ state: OpaquePointer) {
        // Remove filesystem/process execution globals
        let blockedGlobals = ["io", "dofile", "loadfile"]
        for name in blockedGlobals {
            lua_pushnil(state)
            lua_setglobal(state, name)
        }

        // Strip dangerous os.* functions while keeping time/date/clock
        lua_getglobal(state, "os")
        if clua_istable(state, -1) != 0 {
            for fn in ["execute", "remove", "rename", "exit", "setlocale", "tmpname", "getenv"] {
                lua_pushnil(state)
                lua_setfield(state, -2, fn)
            }
        }
        clua_pop(state, 1)

        // Strip package.loadlib
        lua_getglobal(state, "package")
        if clua_istable(state, -1) != 0 {
            lua_pushnil(state)
            lua_setfield(state, -2, "loadlib")
        }
        clua_pop(state, 1)
    }

    // MARK: - Registration

    public func registerFunction(table: String? = nil, name: String, handler: @escaping ([LuaValue]) -> LuaValue) {
        guard let state = L else { return }
        let box = CallbackBox(handler)
        callbackBoxes.append(box)
        let ptr = Unmanaged.passUnretained(box).toOpaque()

        if let table = table {
            lua_getglobal(state, table)
            if clua_istable(state, -1) == 0 {
                clua_pop(state, 1)
                clua_newtable(state)
                lua_pushvalue(state, -1)
                lua_setglobal(state, table)
            }
        }

        lua_pushlightuserdata(state, ptr)
        lua_pushcclosure(state, { co -> Int32 in
            guard let co = co else { return 0 }
            guard let rawPtr = lua_touserdata(co, clua_upvalueindex(1)) else { return 0 }
            let box = Unmanaged<CallbackBox>.fromOpaque(rawPtr).takeUnretainedValue()

            let argc = lua_gettop(co)
            var args: [LuaValue] = []
            if argc > 0 {
                args.reserveCapacity(Int(argc))
                for i in 1...argc {
                    args.append(LuaEngine.readStackValue(co, index: i))
                }
            }

            let result = box.handler(args)
            LuaEngine.pushValue(co, value: result)
            return 1
        }, 1)

        if table != nil {
            lua_setfield(state, -2, name)
            clua_pop(state, 1)
        } else {
            lua_setglobal(state, name)
        }
    }

    @discardableResult
    public func loadPrelude(_ source: String, name: String = "prelude.lua") -> Bool {
        guard let state = L else { return false }
        let loadStatus = luaL_loadbufferx(state, source, source.utf8.count, name, nil)
        if loadStatus != LUA_OK {
            let err = clua_tostring(state, -1).map { String(cString: $0) } ?? "Prelude load error"
            clua_pop(state, 1)
            appendLog(err, isError: true)
            lastError = err
            return false
        }
        let callStatus = clua_pcall(state, 0, 0, 0)
        if callStatus != LUA_OK {
            let err = clua_tostring(state, -1).map { String(cString: $0) } ?? "Prelude runtime error"
            clua_pop(state, 1)
            appendLog(err, isError: true)
            lastError = err
            return false
        }
        return true
    }

    // MARK: - Coroutine Execution

    public func run(_ source: String, name: String = "script.lua") {
        stop()
        guard let state = L else { return }

        lastError = nil
        stopRequested = false

        guard let co = lua_newthread(state) else {
            appendLog("Failed to create Lua coroutine", isError: true)
            return
        }
        threadRef = luaL_ref(state, clua_registry_index())
        activeThread = co

        if let box = selfBox {
            lua_sethook(co, { curCo, _ in
                guard let curCo = curCo else { return }
                lua_getglobal(curCo, "__lucent_stop_flag")
                let shouldStop = lua_toboolean(curCo, -1) != 0
                clua_pop(curCo, 1)
                if shouldStop {
                    _ = clua_error(curCo, "Script stopped")
                }
            }, LUA_MASKCOUNT, 50_000)
            _ = box
        }

        lua_pushboolean(state, 0)
        lua_setglobal(state, "__lucent_stop_flag")

        let loadStatus = luaL_loadbufferx(co, source, source.utf8.count, name, nil)
        if loadStatus != LUA_OK {
            let err = clua_tostring(co, -1).map { String(cString: $0) } ?? "Syntax error"
            clua_pop(co, 1)
            finishRun(error: err)
            return
        }

        isRunning = true
        statusText = "Running \(name)"
        stepResume(nargs: 0)
    }

    public func stop() {
        stopRequested = true
        resumeTimer?.invalidate()
        resumeTimer = nil

        if let state = L {
            lua_pushboolean(state, 1)
            lua_setglobal(state, "__lucent_stop_flag")
            if threadRef != LUA_NOREF {
                luaL_unref(state, clua_registry_index(), threadRef)
                threadRef = LUA_NOREF
            }
        }
        activeThread = nil
        if isRunning {
            isRunning = false
            statusText = "Stopped"
            appendLog("Script stopped.", isError: false)
        }
    }

    public func clearLogs() {
        consoleLogs.removeAll()
    }

    private func stepResume(nargs: Int32) {
        guard !stopRequested, let state = L, let co = activeThread else { return }

        var nresults: Int32 = 0
        let status = lua_resume(co, state, nargs, &nresults)

        if status == LUA_OK {
            if nresults > 0 { clua_pop(co, nresults) }
            finishRun(error: nil)
            return
        }

        if status == LUA_YIELD {
            var delayMs: Double = 16
            if nresults > 0 {
                delayMs = max(1, lua_tonumberx(co, -1, nil))
                clua_pop(co, nresults)
            }
            resumeTimer?.invalidate()
            resumeTimer = Timer.scheduledTimer(withTimeInterval: delayMs / 1000.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.stepResume(nargs: 0)
                }
            }
            return
        }

        let errMsg = clua_tostring(co, -1).map { String(cString: $0) } ?? "Runtime error (\(status))"
        clua_pop(co, 1)
        finishRun(error: errMsg)
    }

    private func finishRun(error: String?) {
        resumeTimer?.invalidate()
        resumeTimer = nil
        if let state = L, threadRef != LUA_NOREF {
            luaL_unref(state, clua_registry_index(), threadRef)
            threadRef = LUA_NOREF
        }
        activeThread = nil
        isRunning = false

        if let error = error {
            lastError = error
            statusText = "Error"
            appendLog(error, isError: true)
        } else {
            statusText = "Finished"
        }
    }

    public func appendLog(_ message: String, isError: Bool) {
        let entry = ScriptLogEntry(
            timestamp: formatter.string(from: Date()),
            message: message,
            isError: isError
        )
        consoleLogs.append(entry)
        if consoleLogs.count > 400 {
            consoleLogs.removeFirst(consoleLogs.count - 400)
        }
    }

    // MARK: - Stack Marshaling

    private static func pushValue(_ L: OpaquePointer, value: LuaValue) {
        switch value {
        case .nil:
            lua_pushnil(L)
        case .bool(let b):
            lua_pushboolean(L, b ? 1 : 0)
        case .int(let i):
            lua_pushinteger(L, lua_Integer(i))
        case .double(let d):
            lua_pushnumber(L, d)
        case .string(let s):
            lua_pushstring(L, s)
        case .array(let arr):
            lua_createtable(L, Int32(arr.count), 0)
            for (idx, item) in arr.enumerated() {
                pushValue(L, value: item)
                lua_rawseti(L, -2, lua_Integer(idx + 1))
            }
        case .table(let dict):
            lua_createtable(L, 0, Int32(dict.count))
            for (k, v) in dict {
                pushValue(L, value: v)
                lua_setfield(L, -2, k)
            }
        }
    }

    private static func readStackValue(_ L: OpaquePointer, index: Int32) -> LuaValue {
        let t = lua_type(L, index)
        switch t {
        case LUA_TNIL, LUA_TNONE:
            return .nil
        case LUA_TBOOLEAN:
            return .bool(lua_toboolean(L, index) != 0)
        case LUA_TNUMBER:
            if lua_isinteger(L, index) != 0 {
                return .int(Int(lua_tointegerx(L, index, nil)))
            }
            return .double(lua_tonumberx(L, index, nil))
        case LUA_TSTRING:
            if let cStr = clua_tostring(L, index) {
                return .string(String(cString: cStr))
            }
            return .string("")
        case LUA_TTABLE:
            let absIdx = lua_absindex(L, index)
            let len = Int(clua_len(L, absIdx))
            var dict: [String: LuaValue] = [:]
            var isArray = len > 0
            lua_pushnil(L)
            while lua_next(L, absIdx) != 0 {
                let key = readStackValue(L, index: -2)
                let val = readStackValue(L, index: -1)
                clua_pop(L, 1)
                if case .int(let kInt) = key, kInt >= 1 && kInt <= len {
                    dict["\(kInt)"] = val
                } else {
                    isArray = false
                    if let ks = key.stringValue {
                        dict[ks] = val
                    }
                }
            }
            if isArray {
                var arr: [LuaValue] = []
                arr.reserveCapacity(len)
                for i in 1...len {
                    arr.append(dict["\(i)"] ?? .nil)
                }
                return .array(arr)
            }
            return .table(dict)
        default:
            return .nil
        }
    }
}
