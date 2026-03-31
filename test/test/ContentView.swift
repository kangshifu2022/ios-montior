import SwiftUI

struct ContentView: View {
    @State private var count = 0
    
    var body: some View {
        VStack(spacing: 40) {
            Text("计数器")
                .font(.largeTitle)
                .bold()
            
            Text("\(count)")
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(.blue)
            
            HStack(spacing: 40) {
                Button("-") { count -= 1 }
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                
                Button("+") { count += 1 }
                    .font(.system(size: 50))
                    .foregroundColor(.green)
            }
            
            Button("重置") { count = 0 }
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    ContentView()
}