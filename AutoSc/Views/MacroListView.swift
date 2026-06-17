import SwiftUI

struct MacroListView: View {
    @State private var macros: [MacroFile] = []
    @StateObject private var player = MacroPlayer()
    @State private var repeatCount = 1
    @State private var playingMacroId: UUID?

    var body: some View {
        NavigationView {
            Group {
                if macros.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No saved macros yet.\nRecord some touches first!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        ForEach(macros) { macro in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(macro.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(macro.actions.count) actions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("\(String(format: "%.1f", macro.duration))s")
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                    Text("·")
                                        .foregroundColor(.secondary)
                                    Text(macro.modifiedAt, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    if playingMacroId == macro.id && player.state == .playing {
                                        Text("Playing \(Int(player.progress * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }

                                if playingMacroId != macro.id || player.state != .playing {
                                    HStack(spacing: 12) {
                                        Stepper("Repeat: \(repeatCount)x", value: $repeatCount, in: 1...100)
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Button(action: { playMacro(macro) }) {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundColor(.green)
                                        }

                                        Button(action: { deleteMacro(macro) }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                } else {
                                    Button(action: { player.stop(); playingMacroId = nil }) {
                                        Label("Stop", systemImage: "stop.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Macros")
            .onAppear { reload() }
            .onReceive(player.$state) { s in
                if s == .completed { playingMacroId = nil }
            }
        }
    }

    private func reload() {
        macros = MacroStore.loadAll()
    }

    private func playMacro(_ macro: MacroFile) {
        playingMacroId = macro.id
        player.loadActions(macro.actions)
        player.play(loopCount: repeatCount)
    }

    private func deleteMacro(_ macro: MacroFile) {
        try? MacroStore.delete(macro)
        reload()
    }
}
