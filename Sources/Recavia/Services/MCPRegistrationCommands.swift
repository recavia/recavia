import Foundation
import RecaviaRuntimeSupport

struct MCPRegistrationCommands: Equatable {
    let codex: String
    let claude: String

    init(
        helperURL: URL,
        vaultID: UUID,
        runtimeProfile: RecaviaRuntimeProfile = RecaviaApplicationSupport.profile()
    ) {
        let helper = Self.shellQuote(helperURL.path)
        let vault = Self.shellQuote(vaultID.uuidString)
        let invocation = Self.helperInvocation(helper: helper, runtimeProfile: runtimeProfile)
        codex = """
        codex mcp remove dahlia
        codex mcp remove recavia
        codex mcp add recavia -- \(invocation) --vault-id \(vault)
        """
        claude = """
        claude mcp remove --scope user dahlia
        claude mcp remove --scope user recavia
        claude mcp add --scope user recavia -- \(invocation) --vault-id \(vault)
        """
    }

    private static func helperInvocation(helper: String, runtimeProfile: RecaviaRuntimeProfile) -> String {
        guard runtimeProfile == .development else { return helper }
        let assignment = shellQuote(
            "\(RecaviaApplicationSupport.profileEnvironmentKey)=\(RecaviaRuntimeProfile.development.rawValue)"
        )
        return "/usr/bin/env \(assignment) \(helper)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
