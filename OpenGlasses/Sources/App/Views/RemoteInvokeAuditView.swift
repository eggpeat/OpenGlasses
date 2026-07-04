import SwiftUI

/// Inspectable audit trail for remote-invoke exchanges (Plan BH): what the gateway agent asked
/// for, and what happened — allowed, denied (with reason), declined by the user, or failed.
struct RemoteInvokeAuditView: View {
    @ObservedObject var service: RemoteInvokeService

    var body: some View {
        List {
            if service.auditLog.isEmpty {
                Text("No remote commands yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.auditLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.action)
                                .font(.body.monospaced())
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.disposition)
                            .font(.caption)
                            .foregroundStyle(entry.disposition == "allowed" ? .green : .orange)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Remote Activity")
        .toolbar {
            if !service.auditLog.isEmpty {
                Button("Clear") { service.clearAudit() }
            }
        }
    }
}
