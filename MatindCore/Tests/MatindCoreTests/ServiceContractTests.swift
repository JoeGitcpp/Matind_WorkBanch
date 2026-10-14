import CryptoKit
import Foundation
import Testing
@testable import MatindCore

/// Runs the shared service-v1 conformance samples (vendored from MatindBackend_Rust,
/// `crates/matrix-automation/contracts/service-v1`) through the Swift validator.
@Suite("服务容器契约")
struct ServiceContractTests {
    private struct Sample {
        let stem: String
        let contract: ServiceContract
        let value: ServiceJSON
    }

    private static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("service-v1")
    }

    private static func samples(_ dir: String) throws -> [Sample] {
        let folder = root.appendingPathComponent(dir)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return try files.map { file in
            let stem = String(file.dropLast(".json".count))
            let name = String(stem.components(separatedBy: "--")[0])
            let contract = try #require(ServiceContract(rawValue: name), "unknown contract \(name)")
            let data = try Data(contentsOf: folder.appendingPathComponent(file))
            return Sample(stem: stem, contract: contract, value: try ServiceJSON.parse(data))
        }
    }

    @Test("每个合法样例都被接受")
    func validSamplesAreAccepted() throws {
        for sample in try Self.samples("valid") {
            do {
                try ServiceContractValidator.validate(sample.contract, sample.value)
            } catch {
                Issue.record("\(sample.stem) rejected: \(error)")
            }
        }
    }

    @Test("每个非法样例都被拒绝")
    func invalidSamplesAreRejected() throws {
        for sample in try Self.samples("invalid") {
            #expect(throws: ServiceContractError.self, "\(sample.stem) was accepted") {
                try ServiceContractValidator.validate(sample.contract, sample.value)
            }
        }
    }

    @Test("每份契约都有合法与非法样例")
    func everyContractHasBothKinds() throws {
        for dir in ["valid", "invalid"] {
            let have = Set(try Self.samples(dir).map(\.contract))
            for contract in ServiceContract.allCases {
                #expect(have.contains(contract), "\(dir) has no sample for \(contract.rawValue)")
            }
        }
    }

    @Test("样例副本与后端一致")
    func vendoredCopyMatchesSums() throws {
        let sums = try String(contentsOf: Self.root.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        let lines = sums.split(separator: "\n").map(String.init)
        let total = try Self.samples("valid").count + Self.samples("invalid").count
        #expect(lines.count == total)
        for line in lines {
            let parts = line.components(separatedBy: "  ")
            let data = try Data(contentsOf: Self.root.appendingPathComponent(parts[1]))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == parts[0], "\(parts[1])")
        }
    }

    @Test("能力编码")
    func capabilityCodes() throws {
        #expect(try ServiceContractValidator.capabilityCode(serviceId: "com.matind.echo", operation: "echo")
            == "local.service.com.matind.echo.echo")
        #expect(throws: ServiceContractError.self) {
            try ServiceContractValidator.capabilityCode(serviceId: "echo", operation: "echo")
        }
    }
}
