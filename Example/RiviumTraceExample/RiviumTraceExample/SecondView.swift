import SwiftUI
import RiviumTrace

struct SecondView: View {
    @State private var statusMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("This view tests auto navigation breadcrumbs")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                DemoButton(title: "Capture Error from Second View", color: .blue) {
                    let error = NSError(
                        domain: "co.rivium.trace.example",
                        code: 2001,
                        userInfo: [NSLocalizedDescriptionKey: "Error from SecondView"]
                    )

                    RiviumTrace.shared.captureError(
                        error,
                        extra: ["screen": "second_view"]
                    ) { success in
                        DispatchQueue.main.async {
                            statusMessage = success ? "Error captured from SecondView!" : "Failed to capture"
                        }
                    }
                }

                DemoButton(title: "Add Navigation Breadcrumb", color: .green) {
                    RiviumTrace.shared.addNavigationBreadcrumb(from: "SecondView", to: "DetailView")
                    statusMessage = "Navigation breadcrumb added"
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Second View")
        .onAppear {
            RiviumTrace.shared.addNavigationBreadcrumb(from: "ContentView", to: "SecondView")
        }
    }
}
