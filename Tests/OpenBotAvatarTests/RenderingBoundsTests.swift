import XCTest
@testable import OpenBotAvatar

final class RenderingBoundsTests: XCTestCase {
    func testExtentContainsBodiesReplacementMarksAndRibbons() throws {
        for id in ["mug", "barbell", "chat", "egg", "ghost"] {
            let avatar = try PreparedAvatar(try XCTUnwrap(AvatarCatalog.definition(id: id)))
            let cap = avatar.extent
            for state in AvatarState.allCases {
                for age in [0.0, 0.15, 0.8, 2.5, 3.8, 7.8] {
                    let frame = avatar.frame(AvatarFrameOptions(time: age, mood: .settled(.happy), state: state, stateAge: age))
                    let bounds = frame.placement().bounds
                    let context = "\(id) \(state) at \(age)"
                    XCTAssertGreaterThanOrEqual(bounds.x0, cap.x, context)
                    XCTAssertGreaterThanOrEqual(bounds.y0, cap.y, context)
                    XCTAssertLessThanOrEqual(bounds.x1, cap.x + cap.size, context)
                    XCTAssertLessThanOrEqual(bounds.y1, cap.y + cap.size, context)
                }
            }
        }
    }
}
