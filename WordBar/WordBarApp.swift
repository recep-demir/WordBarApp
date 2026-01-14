import SwiftUI

@main
struct WordBarApp: App {
    @State private var manager = WordManager()
    @State private var showLoop = false
    @State private var showResetUI = false // New state for in-line reset
    
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                if !showResetUI {
                    // --- NORMAL UI ---
                    if let word = manager.currentWord {
                        HStack(alignment: .firstTextBaseline) {
                            Text(word.word).font(.system(size: 18, weight: .bold))
                            Text("(\(word.pronunciation))").font(.system(size: 14)).foregroundColor(.secondary)
                        }
                        Text(word.meaning).font(.body)
                        Text(word.example).font(.body).italic().foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack {
                            Button("Mark as Learned") {
                                withAnimation { manager.markAsLearned() }
                            }.foregroundColor(.green)
                            
                            if manager.lastLearnedWord != nil {
                                Button("Undo") {
                                    withAnimation { manager.undoLastLearned() }
                                }.foregroundColor(.blue)
                            }
                        }
                    }

                    Divider()

                    Button(showLoop ? "Hide Daily Loop" : "Show Daily Loop (\(manager.dailyWords.count))") {
                        showLoop.toggle()
                    }.buttonStyle(.plain).foregroundColor(.blue)

                    if showLoop {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(manager.dailyWords.enumerated()), id: \.element.id) { index, w in
                                HStack {
                                    Text("• \(w.word)").font(.caption).fontWeight(w == manager.currentWord ? .bold : .regular)
                                    Spacer()
                                    Button(action: { manager.removeFromLoop(at: index) }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                    }.buttonStyle(.plain)
                                }
                            }
                            Button("+ Add New Word to Loop") { manager.addNewWordToLoop() }.font(.caption)
                        }.padding(.leading, 10)
                    }

                    Divider()
                    
                    Group {
                        Toggle("Auto-rotation & Notifications", isOn: $manager.isAutoChangeEnabled)
                        Menu("Update Interval") {
                            Picker("Interval", selection: $manager.selectedInterval) {
                                Text("10 Seconds").tag(TimeInterval(10))
                                Text("15 Minutes").tag(TimeInterval(900))
                                Text("30 Minutes").tag(TimeInterval(1800))
                                Text("45 Minutes").tag(TimeInterval(2700))
                                Text("1 Hour").tag(TimeInterval(3600))
                                Text("2 Hour").tag(TimeInterval(7200))
                            }
                        }
                        Toggle("Launch at Login", isOn: Bindable(manager).isLaunchAtLoginEnabled).toggleStyle(.checkbox)
                    }
                    
                    Divider()
                    
                    HStack {
                        Menu("Maintenance...") {
                            Button("Sync with JSON") { manager.syncWithBundleJSON() }
                            Divider()
                            Button("Reset Data...") { showResetUI = true }
                        }
                        Spacer()
                        Button("Next") { manager.nextWord() }
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                    }
                } else {
                    // --- RESET CONFIRMATION UI ---
                    VStack(spacing: 15) {
                        Text("Reset All Data?").font(.headline).foregroundColor(.red)
                        Text("This will wipe all learned words and start fresh from your JSON file.").font(.caption).multilineTextAlignment(.center)
                        
                        HStack {
                            Button("Yes, Reset Everything") {
                                manager.resetAllData()
                                showResetUI = false
                            }.foregroundColor(.red)
                            
                            Button("Cancel") {
                                showResetUI = false
                            }
                        }
                    }
                    .padding()
                    .frame(width: 280)
                }
            }
            .padding()
            .frame(width: 320)
        } label: {
            Text("本 \(manager.currentWord?.word ?? "---")")
        }
        .menuBarExtraStyle(.window)
    }
}
