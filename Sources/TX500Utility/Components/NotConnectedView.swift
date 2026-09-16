import SwiftUI

/// "Not connected" placeholder shared by every section that needs CAT.
///
/// When the connection dropped for a reason — the radio was switched off, say — that reason is
/// shown here rather than the generic prompt, so every section explains itself without each one
/// having to carry its own banner.
struct NotConnectedView: View {
    @Environment(RadioConnection.self) private var connection
    /// Overrides the default text; the failure reason still wins when there is one.
    var detail: String?

    var body: some View {
        ContentUnavailableView("Not connected", systemImage: "cable.connector", description: Text(message))
    }

    private var message: String {
        if case let .failed(reason) = connection.status { return reason }
        return detail ?? "Choose the CAT cable's port above and press Connect."
    }
}
