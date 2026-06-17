import SwiftUI
import AVFoundation

struct RecordView: View {
    @StateObject private var recorder = TouchRecorder()
    @StateObject private var player = MacroPlayer()
    @State private var macroName = ""
    @State private var showSaveSheet = false
    @State private var savedConfirmation = false
    @State private var repeatCount = 1
    @State private var isOverlayActive = false

    private let injector = TouchInjector.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.9).ignoresSafeArea()

                VStack(spacing: 16) {
                    statusSection
                    controlSection
                    actionListSection
                }
                .padding()
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(recorder.state == .recording ? Color.red : (player.state == .playing ? Color.green : Color.gray))
                    .frame(width: 10, height: 10)
                Text(recorder.state == .recording ? "Recording \(String(format: "%.1fs", recorder.elapsedTime))" :
                     player.state == .playing ? "Playing \(Int(player.progress * 100))%" :
                     "Idle")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(injector.method)
                    .font(.caption)
                    .foregroundColor(injector.canInject ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
            }

            if recorder.state == .recording {
                Text("\(recorder.actions.count) actions captured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var controlSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                if recorder.state == .recording {
                    Button(action: { saveRecording() }) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                } else {
                    Button(action: { recorder.startRecording() }) {
                        Label("Record", systemImage: "record.circle")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(12)
                    }
                }

                if !recorder.actions.isEmpty && recorder.state != .recording {
                    Button(action: playRecording) {
                        Label("Play", systemImage: "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(12)
                    }
                }

                if player.state == .playing {
                    Button(action: { player.stop() }) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                }
            }

            if !recorder.actions.isEmpty && recorder.state != .recording {
                HStack(spacing: 12) {
                    Text("Repeat:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Stepper("\(repeatCount)x", value: $repeatCount, in: 1...100)
                        .foregroundColor(.white)

                    Spacer()

                    Button("Save") {
                        showSaveSheet = true
                    }
                    .foregroundColor(.cyan)
                    .font(.subheadline.bold())

                    Button("Clear") {
                        recorder.actions.removeAll()
                    }
                    .foregroundColor(.red)
                    .font(.subheadline.bold())
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var actionListSection: some View {
        Group {
            if !recorder.actions.isEmpty {
                List {
                    ForEach(Array(recorder.actions.enumerated()), id: \.element.id) { idx, action in
                        HStack {
                            Text("\(idx + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            actionRow(action)
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
                .listStyle(PlainListStyle())
                .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Tap Record, then interact with the screen.\nTouch events will be captured here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ action: TouchAction) -> some View {
        switch action.type {
        case .tap:
            HStack {
                Image(systemName: "hand.tap")
                    .foregroundColor(.cyan)
                Text("Tap")
                    .foregroundColor(.white)
                if let pt = action.startPoint {
                    Text("(\(Int(pt.x)), \(Int(pt.y)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(action.delay * 1000))ms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .swipe:
            HStack {
                Image(systemName: "hand.draw")
                    .foregroundColor(.green)
                Text("Swipe")
                    .foregroundColor(.white)
                if let s = action.startPoint, let e = action.endPoint {
                    Text("(\(Int(s.x)),\(Int(s.y)))→(\(Int(e.x)),\(Int(e.y)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .longPress:
            HStack {
                Image(systemName: "hand.point.up.left")
                    .foregroundColor(.orange)
                Text("Long Press")
                    .foregroundColor(.white)
                if let pt = action.startPoint {
                    Text("(\(Int(pt.x)), \(Int(pt.y)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .wait:
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.yellow)
                Text("Wait")
                    .foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.2f", action.duration))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveRecording() {
        let _ = recorder.stopRecording()
        showSaveSheet = true
    }

    private func playRecording() {
        let actions = recorder.actions
        player.loadActions(actions)
        player.play(loopCount: repeatCount)
    }
}
