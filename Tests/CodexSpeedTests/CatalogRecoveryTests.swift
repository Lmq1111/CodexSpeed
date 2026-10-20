import XCTest
@testable import CodexSpeed

final class CatalogRecoveryTests: XCTestCase {
    func testSuccessfulRefreshClearsCatalogErrorEvenWhenRowsAreUnchanged() async {
        await MainActor.run {
            let model = AppModel()
            let failure = NSError(domain: "CatalogTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "测试读取失败"])
            model.acceptCatalogResult(.failure(failure))
            XCTAssertTrue(model.displayedError?.contains("测试读取失败") == true)
            model.acceptCatalogResult(.success([]))
            XCTAssertNil(model.displayedError)
            model.acceptCatalogResult(.failure(failure))
            XCTAssertNotNil(model.displayedError)
        }
    }
    func testCatalogRecoveryPreservesAnIndependentServiceError() async {
        await MainActor.run {
            let model = AppModel()
            model.error = "分词词表加载失败"
            model.acceptCatalogResult(.failure(NSError(domain: "CatalogTest", code: 1)))
            model.acceptCatalogResult(.success([]))
            XCTAssertEqual(model.displayedError, "分词词表加载失败")
        }
    }
}
