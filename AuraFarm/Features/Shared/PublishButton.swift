import SwiftUI

/// Sends something to the farm's records, and asks for the sign-in that needs first.
///
/// Every row the app writes is filed under whoever wrote it, so nothing can be published by
/// a phone nobody is signed in on. Rather than hide the button, it offers the sign-in.
struct PublishButton: View {
    var title: String
    /// What to send. Anything thrown is shown under the button, and the send can be tried
    /// again without leaving the screen.
    var send: () async throws -> Void

    @Environment(SupabaseSession.self) private var session

    @State private var step = Step.ready
    @State private var isShowingAccount = false

    private enum Step: Equatable {
        case ready
        case sending
        case sent
        case failed(String)
    }

    var body: some View {
        Group {
            switch session.state {
            case .unavailable:
                note("This build is not set up to publish.")
            case .loading:
                ProgressView()
            case .signedOut:
                tap("Sign in to publish", systemImage: "person.crop.circle") {
                    isShowingAccount = true
                }
            case .signedIn:
                publish
            }
        }
        .sheet(isPresented: $isShowingAccount) { AccountView() }
    }

    @ViewBuilder
    private var publish: some View {
        switch step {
        case .ready:
            tap(title, systemImage: "arrow.up.circle") { Task { await run() } }
        case .sending:
            HStack {
                ProgressView()
                Text("Publishing")
            }
        case .sent:
            Label("Published", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let problem):
            tap("Try publishing again", systemImage: "arrow.up.circle") { Task { await run() } }
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func tap(_ title: String, systemImage: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func run() async {
        step = .sending
        do {
            try await send()
            step = .sent
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
