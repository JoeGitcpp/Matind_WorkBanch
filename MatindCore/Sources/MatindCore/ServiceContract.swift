import Foundation

/// Service-container contracts (service-manifest-v1, service-operation-v1,
/// data-handle-v1, capability code, service-task-v1, metering-entry-v1).
///
/// Mirror of `matrix-automation::service_contract` in MatindBackend_Rust. The Rust
/// validator is the reference; all three implementations must reach the same
/// verdict on every file in `Tests/MatindCoreTests/Resources/service-v1`.
/// Unknown fields are rejected everywhere.
public enum ServiceContract: String, CaseIterable, Sendable {
    case manifest = "service-manifest-v1"
    case operation = "service-operation-v1"
    case dataHandle = "data-handle-v1"
    case capability = "capability"
    case task = "service-task-v1"
    case metering = "metering-entry-v1"

    public static let capabilityPrefix = "local.service."
    public static let maxCapabilityBytes = 200
    public static let maxSchemaBytes = 16384
    public static let maxPayloadBytes = 65536
}

/// Minimal JSON tree that keeps integers distinct from fractions and booleans.
public enum ServiceJSON: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([ServiceJSON])
    case object([String: ServiceJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ServiceJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: ServiceJSON].self)) }
    }

    public static func parse(_ data: Data) throws -> ServiceJSON {
        try JSONDecoder().decode(ServiceJSON.self, from: data)
    }

    /// Compact serialisation used only for size limits.
    var serializedByteCount: Int {
        switch self {
        case .null: return 4
        case .bool(let b): return b ? 4 : 5
        case .int(let i): return String(i).utf8.count
        case .double(let d): return String(d).utf8.count
        case .string(let s):
            let escaped = s.unicodeScalars.reduce(0) { n, u in
                n + (u == "\"" || u == "\\" || u.value < 0x20 ? 2 : String(u).utf8.count)
            }
            return escaped + 2
        case .array(let a): return 2 + a.reduce(0) { $0 + $1.serializedByteCount } + max(0, a.count - 1)
        case .object(let o):
            return 2 + o.reduce(0) { $0 + ServiceJSON.string($1.key).serializedByteCount + 1 + $1.value.serializedByteCount }
                + max(0, o.count - 1)
        }
    }
}

public struct ServiceContractError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum ServiceContractValidator {
    /// Validates `value` against `contract`. Throws `ServiceContractError` when rejected.
    public static func validate(_ contract: ServiceContract, _ value: ServiceJSON) throws {
        switch contract {
        case .manifest: try validateManifest(value)
        case .operation: try validateOperation(value)
        case .dataHandle: try validateDataHandle(value)
        case .capability:
            guard case .string(let s) = value else { throw fail("capability: expected string") }
            try validateCapability(s)
        case .task: try validateTask(value)
        case .metering: try validateMetering(value)
        }
    }

    // MARK: primitives

    private static func fail(_ message: String) -> ServiceContractError { ServiceContractError(message: message) }

    private static func isLowerAlpha(_ b: UInt8) -> Bool { b >= 0x61 && b <= 0x7a }
    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    private static func isAlnum(_ b: UInt8) -> Bool { isDigit(b) || isLowerAlpha(b) || (b >= 0x41 && b <= 0x5a) }

    static func identOk(_ s: String, _ max: Int) -> Bool {
        let b = Array(s.utf8)
        return !b.isEmpty && b.count <= max && isLowerAlpha(b[0])
            && b.allSatisfy { isLowerAlpha($0) || isDigit($0) || $0 == 0x5f }
    }

    static func opaqueIdOk(_ s: String) -> Bool {
        let b = Array(s.utf8)
        return !b.isEmpty && b.count <= 64 && b.allSatisfy { isAlnum($0) || $0 == 0x5f || $0 == 0x2d }
    }

    public static func serviceIdOk(_ s: String) -> Bool {
        guard s.utf8.count <= 128 else { return false }
        let segments = s.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count >= 2 && segments.allSatisfy { seg in
            let b = Array(seg.utf8)
            return !b.isEmpty && b.count <= 63 && b.first != 0x2d && b.last != 0x2d
                && b.allSatisfy { isLowerAlpha($0) || isDigit($0) || $0 == 0x2d }
        }
    }

    public static func operationNameOk(_ s: String) -> Bool { identOk(s, 64) }

    static func semverOk(_ s: String) -> Bool {
        guard s.utf8.count <= 64 else { return false }
        let halves = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = halves[0]
        let pre: Substring? = halves.count > 1 ? halves[1] : nil
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        func num(_ p: Substring) -> Bool {
            let b = Array(p.utf8)
            return !b.isEmpty && b.count <= 9 && b.allSatisfy(isDigit) && (p == "0" || b[0] != 0x30)
        }
        guard parts.count == 3, parts.allSatisfy(num) else { return false }
        if let pre {
            let b = Array(pre.utf8)
            return !b.isEmpty && b.count <= 32 && b.allSatisfy { isAlnum($0) || $0 == 0x2e || $0 == 0x2d }
        }
        return true
    }

    static func sha256Ok(_ s: String) -> Bool {
        let b = Array(s.utf8)
        return b.count == 64 && b.allSatisfy { isDigit($0) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// UTC only, `YYYY-MM-DDTHH:MM:SSZ`.
    static func timestampOk(_ s: String) -> Bool {
        let b = Array(s.utf8)
        guard b.count == 20 else { return false }
        let digits = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        guard digits.allSatisfy({ isDigit(b[$0]) }),
              b[4] == 0x2d, b[7] == 0x2d, b[10] == 0x54, b[13] == 0x3a, b[16] == 0x3a, b[19] == 0x5a
        else { return false }
        func n(_ i: Int) -> Int { Int(b[i] - 0x30) * 10 + Int(b[i + 1] - 0x30) }
        return (1...12).contains(n(5)) && (1...31).contains(n(8)) && n(11) <= 23 && n(14) <= 59 && n(17) <= 59
    }

    /// Only numeric loopback hosts. No names, no userinfo, no query, no fragment.
    static func loopbackEndpointOk(_ s: String) -> Bool {
        guard s.utf8.count <= 256 else { return false }
        var rest: Substring
        if s.hasPrefix("http://127.0.0.1:") { rest = s.dropFirst("http://127.0.0.1:".count) }
        else if s.hasPrefix("http://[::1]:") { rest = s.dropFirst("http://[::1]:".count) }
        else { return false }
        let slash = rest.firstIndex(of: "/")
        let port = slash.map { rest[rest.startIndex..<$0] } ?? rest
        let path = slash.map { rest[$0...] } ?? ""
        let pb = Array(port.utf8)
        guard !pb.isEmpty, pb.count <= 5, pb.allSatisfy(isDigit), let p = Int(port), (1...65535).contains(p)
        else { return false }
        return !path.contains { "@?#\\".contains($0) }
    }

    static func relativePathOk(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 256, !s.hasPrefix("/"), !s.contains("\\"), !s.contains(":")
        else { return false }
        return s.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    public static func validateCapability(_ s: String) throws {
        guard s.hasPrefix(ServiceContract.capabilityPrefix) else { throw fail("capability: missing local.service. prefix") }
        guard s.utf8.count <= ServiceContract.maxCapabilityBytes else { throw fail("capability: too long") }
        let rest = s.dropFirst(ServiceContract.capabilityPrefix.count)
        guard let dot = rest.lastIndex(of: ".") else { throw fail("capability: missing operation") }
        guard serviceIdOk(String(rest[rest.startIndex..<dot])) else { throw fail("capability: invalid serviceId") }
        guard operationNameOk(String(rest[rest.index(after: dot)...])) else { throw fail("capability: invalid operation") }
    }

    /// `local.service.<serviceId>.<operation>`
    public static func capabilityCode(serviceId: String, operation: String) throws -> String {
        let code = "\(ServiceContract.capabilityPrefix)\(serviceId).\(operation)"
        try validateCapability(code)
        return code
    }

    // MARK: field access

    /// Tracks which keys were read so leftovers can be rejected.
    private final class Obj {
        let name: String
        let map: [String: ServiceJSON]
        var seen = Set<String>()

        init(_ name: String, _ value: ServiceJSON?) throws {
            guard case .object(let m)? = value else { throw ServiceContractError(message: "\(name): expected object") }
            self.name = name
            self.map = m
        }
        func get(_ key: String) -> ServiceJSON? { seen.insert(key); return map[key] }
        func req(_ key: String) throws -> ServiceJSON {
            guard let v = get(key) else { throw ServiceContractError(message: "\(name).\(key): required") }
            return v
        }
        func str(_ key: String) throws -> String {
            guard case .string(let s) = try req(key) else { throw ServiceContractError(message: "\(name).\(key): expected string") }
            return s
        }
        func optStr(_ key: String, _ max: Int) throws {
            guard let v = get(key) else { return }
            guard case .string(let s) = v, s.utf8.count <= max else {
                throw ServiceContractError(message: "\(name).\(key): expected string up to \(max) bytes")
            }
        }
        func bool(_ key: String) throws -> Bool {
            guard case .bool(let b) = try req(key) else { throw ServiceContractError(message: "\(name).\(key): expected boolean") }
            return b
        }
        @discardableResult
        func uint(_ key: String, _ min: Int64, _ max: Int64) throws -> Int64 {
            guard case .int(let n) = try req(key), n >= min, n <= max else {
                throw ServiceContractError(message: "\(name).\(key): expected integer \(min)...\(max)")
            }
            return n
        }
        @discardableResult
        func oneOf(_ key: String, _ allowed: [String]) throws -> String {
            let s = try str(key)
            guard allowed.contains(s) else { throw ServiceContractError(message: "\(name).\(key): must be one of \(allowed)") }
            return s
        }
        @discardableResult
        func checkStr(_ key: String, _ ok: (String) -> Bool) throws -> String {
            let s = try str(key)
            guard ok(s) else { throw ServiceContractError(message: "\(name).\(key): invalid") }
            return s
        }
        @discardableResult
        func opaqueId(_ key: String) throws -> String { try checkStr(key, ServiceContractValidator.opaqueIdOk) }
        func optOpaqueId(_ key: String) throws {
            guard let v = get(key) else { return }
            guard case .string(let s) = v, ServiceContractValidator.opaqueIdOk(s) else {
                throw ServiceContractError(message: "\(name).\(key): invalid")
            }
        }
        func contract(_ expected: String) throws {
            guard try str("contract") == expected else { throw ServiceContractError(message: "\(name).contract: expected \(expected)") }
        }
        func object(_ key: String) throws -> ServiceJSON {
            let v = try req(key)
            guard case .object = v else { throw ServiceContractError(message: "\(name).\(key): expected object") }
            return v
        }
        func finish() throws {
            for key in map.keys where !seen.contains(key) {
                throw ServiceContractError(message: "\(name): unknown field \(key)")
            }
        }
    }

    private static func payloadOk(_ name: String, _ v: ServiceJSON, _ limit: Int) throws {
        guard case .object = v else { throw fail("\(name): expected object") }
        guard v.serializedByteCount <= limit else { throw fail("\(name): exceeds \(limit) bytes") }
    }

    private static func jsonSchemaOk(_ name: String, _ v: ServiceJSON) throws {
        try payloadOk(name, v, ServiceContract.maxSchemaBytes)
        guard case .object(let m) = v, case .string("object")? = m["type"] else {
            throw fail("\(name): schema root must have type \"object\"")
        }
    }

    // MARK: manifest

    private static func validateManifest(_ v: ServiceJSON) throws {
        let o = try Obj("manifest", v)
        try o.contract("service-manifest-v1")
        try o.checkStr("serviceId", serviceIdOk)
        try o.checkStr("version", semverOk)
        let source = try o.oneOf("source", ["official", "third_party"])
        try o.optStr("displayName", 64)

        let d = try Obj("manifest.driver", try o.object("driver"))
        let driver = try d.oneOf("kind", ["external", "process", "container"])
        switch driver {
        case "external":
            try d.checkStr("endpoint", loopbackEndpointOk)
        case "process":
            try d.checkStr("package", opaqueIdOk)
            try d.checkStr("entry", relativePathOk)
            if let args = d.get("args") {
                guard case .array(let a) = args, a.count <= 16, a.allSatisfy({
                    if case .string(let s) = $0 { return s.utf8.count <= 256 } else { return false }
                }) else { throw fail("manifest.driver.args: expected up to 16 strings") }
            }
        default:
            let image = try d.str("image")
            if image.isEmpty || image.utf8.count > 256
                || image.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control }) {
                throw fail("manifest.driver.image: invalid")
            }
            _ = try d.bool("gpu")
        }
        try d.finish()
        if source == "third_party" && driver == "process" {
            throw fail("manifest.driver: third_party services cannot use the process driver")
        }

        guard case .array(let ops) = try o.req("operations") else { throw fail("manifest.operations: expected array") }
        guard (1...64).contains(ops.count) else { throw fail("manifest.operations: expected 1..=64 entries") }
        var names = Set<String>()
        for op in ops {
            let name = try validateManifestOperation(op)
            guard names.insert(name).inserted else { throw fail("manifest.operations: duplicate \(name)") }
        }

        let r = try Obj("manifest.resources", try o.object("resources"))
        try r.uint("diskMb", 0, 100_000_000)
        try r.uint("memoryMb", 0, 10_000_000)
        _ = try r.bool("gpu")
        try r.uint("maxConcurrency", 1, 64)
        try r.finish()

        if let cfg = o.get("config") {
            guard case .array(let items) = cfg else { throw fail("manifest.config: expected array") }
            guard items.count <= 64 else { throw fail("manifest.config: too many fields") }
            var keys = Set<String>()
            for item in items {
                let key = try validateConfigField(item)
                guard keys.insert(key).inserted else { throw fail("manifest.config: duplicate \(key)") }
            }
        }

        let h = try Obj("manifest.health", try o.object("health"))
        let kind = try h.oneOf("kind", ["http", "operation", "process"])
        try h.uint("intervalSec", 5, 3600)
        switch kind {
        case "http":
            let t = try h.str("target")
            if !t.hasPrefix("/") || t.utf8.count > 256 || t.contains(where: { "?#\\".contains($0) }) {
                throw fail("manifest.health.target: invalid path")
            }
        case "operation":
            guard names.contains(try h.str("target")) else { throw fail("manifest.health.target: unknown operation") }
        default:
            if h.get("target") != nil { throw fail("manifest.health.target: not allowed for process") }
        }
        try h.finish()

        if let kinds = o.get("modelKinds") {
            guard case .array(let a) = kinds, a.count <= 8, a.allSatisfy({
                if case .string(let s) = $0 { return identOk(s, 32) } else { return false }
            }) else { throw fail("manifest.modelKinds: invalid") }
        }
        try o.finish()
    }

    private static func validateManifestOperation(_ v: ServiceJSON) throws -> String {
        let o = try Obj("manifest.operation", v)
        let name = try o.checkStr("name", operationNameOk)
        try o.optStr("description", 256)
        try jsonSchemaOk("manifest.operation.inputSchema", try o.req("inputSchema"))
        try jsonSchemaOk("manifest.operation.outputSchema", try o.req("outputSchema"))
        _ = try o.bool("longRunning")
        let s = try Obj("manifest.operation.streams", try o.object("streams"))
        _ = try s.bool("consumes")
        try s.oneOf("produces", ["none", "workspace_storage", "server_hold"])
        try s.finish()
        try o.checkStr("meteringUnit") { identOk($0, 32) }
        try o.finish()
        return name
    }

    private static func validateConfigField(_ v: ServiceJSON) throws -> String {
        let o = try Obj("manifest.config.field", v)
        let key = try o.checkStr("key") { identOk($0, 64) }
        let type = try o.oneOf("type", ["string", "integer", "boolean", "secret"])
        let label = try o.str("label")
        if label.isEmpty || label.utf8.count > 64 { throw fail("manifest.config.field.label: invalid") }
        _ = try o.bool("required")
        if let def = o.get("default") {
            let fits: Bool
            switch (type, def) {
            case ("string", .string(let s)): fits = s.utf8.count <= 256
            case ("integer", .int): fits = true
            case ("boolean", .bool): fits = true
            default: fits = false
            }
            if !fits { throw fail("manifest.config.field.default: does not match type") }
        }
        try o.finish()
        return key
    }

    // MARK: operation

    private static func validateOperation(_ v: ServiceJSON) throws {
        let o = try Obj("operation", v)
        try o.contract("service-operation-v1")
        try o.opaqueId("taskId")
        switch try o.oneOf("kind", ["call", "progress", "cancel", "result"]) {
        case "call":
            try o.checkStr("serviceId", serviceIdOk)
            try o.checkStr("operation", operationNameOk)
            try payloadOk("operation.input", try o.req("input"), ServiceContract.maxPayloadBytes)
        case "progress":
            let p: Double
            switch try o.req("progress") {
            case .int(let i): p = Double(i)
            case .double(let d): p = d
            default: throw fail("operation.progress: expected number 0..=1")
            }
            guard (0.0...1.0).contains(p) else { throw fail("operation.progress: expected number 0..=1") }
            try o.optStr("message", 256)
        case "cancel":
            try o.optStr("reason", 256)
        default:
            if try o.oneOf("status", ["ok", "error"]) == "ok" {
                try payloadOk("operation.output", try o.req("output"), ServiceContract.maxPayloadBytes)
            } else {
                let e = try Obj("operation.error", try o.object("error"))
                try e.checkStr("code") { identOk($0, 64) }
                guard try e.str("message").utf8.count <= 512 else { throw fail("operation.error.message: too long") }
                try e.finish()
            }
        }
        try o.finish()
    }

    // MARK: data handle

    private static func validateDataHandle(_ v: ServiceJSON) throws {
        let o = try Obj("dataHandle", v)
        try o.contract("data-handle-v1")
        try o.opaqueId("handleId")
        try o.oneOf("destination", ["workspace_storage", "server_hold"])
        try o.uint("sizeBytes", 0, 1 << 50)
        try o.checkStr("sha256", sha256Ok)
        try o.checkStr("expiresAt", timestampOk)
        try o.optStr("mediaType", 128)
        try o.finish()
    }

    // MARK: task

    private static func validateTask(_ v: ServiceJSON) throws {
        let o = try Obj("task", v)
        try o.contract("service-task-v1")
        try o.opaqueId("taskId")
        try o.opaqueId("workspaceId")
        try o.opaqueId("callerId")
        try o.optOpaqueId("blueprintId")
        let status = try o.oneOf("status", ["queued", "dispatched", "running", "succeeded", "failed", "cancelled", "outcome_unknown"])
        // The executing server is chosen at dispatch time: absent while queued,
        // required from dispatch on, optional once cancelled.
        let server = o.get("serverId")
        var serverOk = false
        if case .string(let s)? = server { serverOk = opaqueIdOk(s) }
        let absentOk = server == nil && (status == "queued" || status == "cancelled")
        let presentOk = serverOk && status != "queued"
        guard absentOk || presentOk else { throw fail("task.serverId: absent while queued, required once dispatched") }
        try o.checkStr("serviceId", serviceIdOk)
        try o.checkStr("operation", operationNameOk)
        let p = try Obj("task.payer", try o.object("payer"))
        try p.oneOf("kind", ["caller", "runner", "blueprint_owner", "transferor"])
        try p.opaqueId("userId")
        try p.finish()
        try o.checkStr("meteringUnit") { identOk($0, 32) }
        try o.checkStr("createdAt", timestampOk)
        try o.finish()
    }

    // MARK: metering

    private static func validateMetering(_ v: ServiceJSON) throws {
        let o = try Obj("metering", v)
        try o.contract("metering-entry-v1")
        for key in ["entryId", "taskId", "workspaceId", "callerId"] { try o.opaqueId(key) }
        try o.optOpaqueId("blueprintId")
        try o.opaqueId("serverId")
        try o.checkStr("serviceId", serviceIdOk)
        try o.checkStr("operation", operationNameOk)
        try o.checkStr("unit") { identOk($0, 32) }
        try o.uint("units", 0, 1 << 50)
        try o.opaqueId("payerId")
        try o.checkStr("createdAt", timestampOk)
        try o.finish()
    }
}
