import Foundation
import Testing
@testable import MatindCore

@Suite("工作板目录")
struct BoardCatalogTests {
    @Test("新页面序号取已有最大值加一")
    func namesSkipToTheNextSequence() {
        #expect(BoardPageName.next(among: []) == "新页面 1")
        #expect(BoardPageName.next(among: ["概览", "新页面 2"]) == "新页面 3")
        #expect(BoardPageName.next(among: ["新页面 2", "新页面 9"]) == "新页面 10")
    }

    @Test("创建请求只包含契约字段")
    func createBodyRejectsUnknownShape() throws {
        let key = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let data = try BoardDocuments.create(name: "新页面 1", idempotencyKey: key)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
        #expect(Set(object.keys) == ["schemaVersion", "name", "idempotencyKey"])
        #expect(object["schemaVersion"] == "1")
        #expect(object["name"] == "新页面 1")
        #expect(object["idempotencyKey"] == "11111111-1111-1111-1111-111111111111")
        #expect(throws: ControlPlaneFailure.self) {
            try BoardDocuments.create(name: " 新页面 ", idempotencyKey: key)
        }
    }

    @Test("删除请求带期望名称和版本，原因缺省时不出现")
    func deleteBodyCarriesPreconditions() throws {
        let key = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let data = try BoardDocuments.delete(
            expectedName: "新页面 1",
            expectedAccessRevision: "3",
            idempotencyKey: key,
            reason: nil
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
        #expect(object["expectedName"] == "新页面 1")
        #expect(object["expectedAccessRevision"] == "3")
        #expect(object.keys.contains("reason") == false)
        #expect(throws: ControlPlaneFailure.self) {
            try BoardDocuments.delete(
                expectedName: "新页面 1",
                expectedAccessRevision: "03",
                idempotencyKey: key,
                reason: nil
            )
        }
    }

    @Test("目录文档解析能力，未知结构版本拒绝")
    func parsesCatalogAndRejectsUnknownSchema() throws {
        let catalog = try BoardReceiptParser.catalog(Data(sampleCatalog.utf8))
        #expect(catalog.boards.count == 1)
        #expect(catalog.boards[0].contentCapability.permitsEditing)
        #expect(catalog.boards[0].settingsCapability.permitsManagement == false)
        var broken = try JSONSerialization.jsonObject(with: Data(sampleCatalog.utf8)) as! [String: Any]
        broken["schemaVersion"] = "2"
        let data = try JSONSerialization.data(withJSONObject: broken)
        #expect(throws: ControlPlaneFailure.self) {
            try BoardReceiptParser.catalog(data)
        }
    }
}

private let sampleCatalog = """
{
  "schemaVersion": "1",
  "workspaceId": "7",
  "boards": [
    {
      "schemaVersion": "1",
      "id": "9",
      "workspaceId": "7",
      "name": "页面",
      "layoutVersion": "1",
      "accessRevision": "4",
      "authorityKind": "workspace",
      "authorityReceiptId": "r1",
      "contentCapability": "edit",
      "settingsCapability": "none"
    }
  ]
}
"""
