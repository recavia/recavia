import SwiftUI

struct CloudStorageSettingsView: View {
    @ObservedObject private var driveStore = GoogleDriveStore.shared

    var body: some View {
        Form {
            Section {
                connectionRow

                if let message = driveStore.lastErrorMessage {
                    SettingsStatusMessage(
                        text: message,
                        systemImage: "exclamationmark.triangle",
                        tint: .orange
                    )
                }
            } header: {
                Text(L10n.googleDocs)
            } footer: {
                Text(L10n.googleDocsSettingsDescription)
            }
        }
        .formStyle(.grouped)
        .task {
            await driveStore.restoreSessionIfNeeded()
        }
    }

    private var connectionRow: some View {
        LabeledContent {
            actionButton
        } label: {
            Text(driveStore.account?.displayName ?? L10n.googleDocsNotConnected)
            Text(accountSubtitle)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if !driveStore.isAuthorized {
            Button(L10n.googleDriveConnect) {
                Task {
                    await driveStore.signIn()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!driveStore.isConfigured || driveStore.isBusy)
        } else {
            Button(L10n.googleDriveDisconnect) {
                Task {
                    await driveStore.disconnect()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!driveStore.isConfigured || driveStore.isBusy)
        }
    }

    private var accountSubtitle: String {
        if !driveStore.isConfigured {
            return L10n.googleAccountClientIDMissingMessage
        }

        if let account = driveStore.account, driveStore.isAuthorized {
            return account.email.isEmpty ? L10n.googleDocsConnected : account.email
        }

        return L10n.googleDocsConnectDescription
    }
}
