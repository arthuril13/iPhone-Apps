import SwiftUI

struct ContentView: View {
    @State private var taps = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.20),
                         Color(red: 0.20, green: 0.10, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("👋")
                    .font(.system(size: 80))

                Text("Hello, world!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("My first iPhone app")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Button {
                    taps += 1
                } label: {
                    Text(taps == 0 ? "Tap me" : "Tapped \(taps)×")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                .padding(.top, 10)
            }
        }
    }
}

#Preview {
    ContentView()
}
