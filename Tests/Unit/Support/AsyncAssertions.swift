import XCTest

@MainActor
func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath, line: UInt = #line,
  _ handler: (Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    XCTFail("Expected an error. " + message(), file: file, line: line)
  } catch {
    handler(error)
  }
}

@MainActor
func XCTAssertNoThrowAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath, line: UInt = #line
) async {
  do {
    _ = try await expression()
  } catch {
    XCTFail("Unexpected error: \(error). " + message(), file: file, line: line)
  }
}
