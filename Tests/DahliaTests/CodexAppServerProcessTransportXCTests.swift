import Darwin
import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct CodexAppServerProcessTransportTests {
        @Test
        func exchangesMultipleLinesWithLongLivedChild() async throws {
            let transport = try CodexAppServerProcessTransport(
                executableURL: URL(fileURLWithPath: "/bin/cat"),
                arguments: []
            )

            try await transport.sendLine(Data("first".utf8))
            #expect(try await transport.receiveLine() == Data("first".utf8))
            try await transport.sendLine(Data("second".utf8))
            #expect(try await transport.receiveLine() == Data("second".utf8))
            await transport.close()
        }

        @Test
        func closeReapsLongLivedChild() async throws {
            let transport = try CodexAppServerProcessTransport(
                executableURL: URL(fileURLWithPath: "/bin/cat"),
                arguments: []
            )
            let processID = await transport.processIdentifierForTesting()

            #expect(Darwin.kill(processID, 0) == 0)
            await transport.close()
            let probeResult = Darwin.kill(processID, 0)
            let probeError = errno
            #expect(probeResult == -1)
            #expect(probeError == ESRCH)
        }
    }
#endif
