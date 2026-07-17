import Foundation
@testable import Recavia

#if canImport(Testing)
    import Testing

    struct MCPRegistrationCommandsTests {
        @Test
        func commandsReplaceOneVaultScopedServerAndQuoteArguments() throws {
            let vaultID = try #require(UUID(uuidString: "019F6651-CCBE-7CF2-83B0-6EF955A9FD41"))
            let commands = MCPRegistrationCommands(
                helperURL: URL(filePath: "/Applications/Recavia's App.app/Contents/Helpers/recavia-mcp"),
                vaultID: vaultID,
                runtimeProfile: .production
            )

            let quotedHelper = "'/Applications/Recavia'\\''s App.app/Contents/Helpers/recavia-mcp'"
            let quotedVault = "'019F6651-CCBE-7CF2-83B0-6EF955A9FD41'"
            #expect(commands
                .codex == "codex mcp remove dahlia\ncodex mcp remove recavia\ncodex mcp add recavia -- \(quotedHelper) --vault-id \(quotedVault)")
            #expect(commands
                .claude ==
                "claude mcp remove --scope user dahlia\nclaude mcp remove --scope user recavia\nclaude mcp add --scope user recavia -- \(quotedHelper) --vault-id \(quotedVault)")
        }

        @Test
        func developmentCommandsPreserveTheDevelopmentProfileForExternalHelpers() throws {
            let vaultID = try #require(UUID(uuidString: "019F6651-CCBE-7CF2-83B0-6EF955A9FD41"))
            let commands = MCPRegistrationCommands(
                helperURL: URL(filePath: "/Applications/Recavia Dev.app/Contents/Helpers/recavia-mcp"),
                vaultID: vaultID,
                runtimeProfile: .development
            )

            let invocation = "/usr/bin/env 'RECAVIA_RUNTIME_PROFILE=development' '/Applications/Recavia Dev.app/Contents/Helpers/recavia-mcp'"
            #expect(commands.codex.contains("-- \(invocation) --vault-id"))
            #expect(commands.claude.contains("-- \(invocation) --vault-id"))
        }
    }
#endif
