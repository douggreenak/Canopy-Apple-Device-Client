import SwiftUI
import AppKit

struct ContentView: View {
    @State var show = true
    var body: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            List {
                Section(header: Text("Today")) {
                    HStack {
                        Text("Row 1")
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing) {
                        Button("Delete") {}
                    }
                }
            }
            .listStyle(.inset)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack {
                Text("Safe Area Inset Bar")
                    .padding()
            }
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let cv = NSHostingView(rootView: ContentView())
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.contentView = cv
        window.makeKeyAndOrderFront(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSApplication.shared.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
