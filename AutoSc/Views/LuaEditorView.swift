import SwiftUI

struct LuaEditorView: View {
    @StateObject private var engine = LuaEngine.shared
    @State private var script: String = ""
    @State private var scriptName: String = "untitled"
    @State private var savedScripts: [URL] = []
    @State private var showSavedList = false
    @State private var showNewTemplate = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                toolbarSection

                if engine.isRunning {
                    runningBar
                }

                TextEditor(text: $script)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.3))
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Lua Editor")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if script.isEmpty {
                    script = LuaEngine.generateTemplate()
                }
                savedScripts = MacroStore.listLuaScripts()
            }
        }
    }

    private var toolbarSection: some View {
        HStack(spacing: 8) {
            Button(action: { script = LuaEngine.generateTemplate() }) {
                Image(systemName: "doc.badge.plus")
                    .foregroundColor(.cyan)
            }

            Button(action: { showSavedList = true }) {
                Image(systemName: "folder")
                    .foregroundColor(.cyan)
            }
            .popover(isPresented: $showSavedList) {
                savedScriptsList
            }

            Spacer()

            if engine.isRunning {
                Button(action: { engine.stop() }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline.bold())
                }
            } else {
                Button(action: runScript) {
                    Label("Run", systemImage: "play.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline.bold())
                }
                .disabled(!TouchInjector.shared.canInject)
            }

            Spacer()

            Button(action: saveScript) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    private var runningBar: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .green))
            Text("Running... Line \(engine.currentLine)")
                .font(.caption)
                .foregroundColor(.green)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
    }

    private var savedScriptsList: some View {
        NavigationView {
            List {
                if savedScripts.isEmpty {
                    Text("No saved scripts")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(savedScripts, id: \.self) { url in
                        Button(action: {
                            if let content = try? String(contentsOf: url, encoding: .utf8) {
                                script = content
                                scriptName = url.deletingPathExtension().lastPathComponent
                            }
                            showSavedList = false
                        }) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.cyan)
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    try? MacroStore.deleteLua(at: url)
                                    savedScripts = MacroStore.listLuaScripts()
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Scripts")
        }
    }

    private func runScript() {
        engine.execute(script)
    }

    private func saveScript() {
        try? MacroStore.saveLua(scriptName, script)
        savedScripts = MacroStore.listLuaScripts()
    }
}
