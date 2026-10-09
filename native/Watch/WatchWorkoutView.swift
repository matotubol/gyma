import Combine
import GymaCore
import SwiftUI

@MainActor
struct WatchWorkoutView: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @EnvironmentObject private var runtime: WatchWorkoutRuntime
    @StateObject private var local = WatchSetFlowStore()
    @State private var editor: WatchValueField?
    @State private var showSettings = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var finishWorkoutID: String?
    @State private var finishRevision: Int?
    @State private var localError: String?
    @State private var settingsAction: WatchSettingsAction?

    private var draft: WatchSetDraft? { local.flow.draft }
    private var canAct: Bool { connectivity.canSubmit && local.storageError == nil }
    private var currentDraft: Bool {
        connectivity.snapshot.map { draft?.matches($0) == true } ?? false
    }
    private var restTimer: RestTimer? {
        connectivity.snapshot?.restTimer ?? local.flow.resumeRestTimer
    }
    private var hasIssues: Bool {
        local.storageError != nil || connectivity.lastError != nil ||
        connectivity.lastAcknowledgement?.status == .rejected || connectivity.quarantinedCommand != nil ||
        runtime.message != nil || notifications.message != nil || (draft != nil && !currentDraft && draft?.phase != .submitting)
    }
    private var statusText: String? {
        if local.storageError != nil || connectivity.lastAcknowledgement?.status == .rejected { return "Change not saved" }
        if connectivity.quarantinedCommand != nil || connectivity.lastError != nil ||
            (restTimer != nil && draft != nil && !currentDraft && draft?.phase != .submitting) { return "Review saved change" }
        if let pending = connectivity.pendingCommand, draft?.phase != .submitting { return pending.action.watchDescription }
        return nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.height < 185
                let showsStatus = geometry.size.height >= 175 && statusText != nil
                let contentHeight = geometry.size.height - (showsStatus ? 18 : 0)
                VStack(spacing: compact ? 3 : 5) {
                    focusedWorkout(compact: compact, availableHeight: contentHeight)
                    if showsStatus { compactStatus }
                }
                .padding(.horizontal, 8)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
            .background(Color.black)
            .navigationTitle("Gyma")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .overlay(alignment: .topTrailing) {
                                if hasIssues || connectivity.pendingCommand != nil {
                                    Circle().fill(hasIssues ? Color.orange : Color.mint).frame(width: 6, height: 6)
                                }
                            }
                    }
                    .accessibilityLabel(hasIssues ? "Workout settings, action needed" : "Workout settings")
                }
            }
            .sheet(item: $editor) { field in valueEditor(field) }
            .sheet(isPresented: $showSettings, onDismiss: handleSettingsAction) {
                WatchWorkoutSettings(storageError: local.storageError, draft: draft, isDraftCurrent: currentDraft,
                                     discardDraft: { settingsAction = .discard; showSettings = false },
                                     finishWorkout: { settingsAction = .finish; showSettings = false })
            }
            .task { reconcile() }
            .onChange(of: connectivity.snapshot) { _, _ in reconcile() }
            .onChange(of: connectivity.pendingCommand) { _, _ in reconcile() }
            .onChange(of: connectivity.lastAcknowledgement) { _, _ in reconcile() }
            .onChange(of: draft?.workingSetCount) { _, _ in editor = nil }
            .onChange(of: draft?.exerciseID) { _, _ in editor = nil }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish workout", role: .destructive) {
                    do {
                        try connectivity.submit(.finishWorkout, expectedWorkoutID: finishWorkoutID,
                                                basedOnRevision: finishRevision)
                    } catch { localError = error.localizedDescription }
                }
                Button("Keep training", role: .cancel) {}
            } message: { Text("Your confirmed sets will be saved on iPhone.") }
            .confirmationDialog("Discard this saved draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) {
                    guard let snapshot = connectivity.snapshot else { return }
                    change { $0.useCurrentWorkout(snapshot) }
                }
                Button("Keep draft", role: .cancel) {}
            } message: { Text("Only this unsent Watch draft will be removed. Your confirmed sets stay saved.") }
            .alert("Could not save the change", isPresented: Binding(
                get: { localError != nil }, set: { if !$0 { localError = nil } }
            )) {
                Button("OK", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
        }
    }

    @ViewBuilder
    private func focusedWorkout(compact: Bool, availableHeight: CGFloat) -> some View {
        if let workout = connectivity.snapshot?.activeWorkout {
            if let timer = restTimer, timer.workoutID == workout.id {
                restScreen(timer, compact: compact)
            } else if let draft, !currentDraft && draft.phase != .submitting {
                draftRecovery
            } else if let draft {
                setScreen(draft, workout: workout, compact: compact, availableHeight: availableHeight)
            } else if hasHiddenExercises(workout) {
                Text("Continue on iPhone to see the remaining exercises.").font(.headline)
            } else if workout.nextExercise == nil {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.mint)
                Text("Workout complete").font(.title3.bold())
                primaryButton("Finish workout", symbol: "checkmark") { prepareFinish(workout) }
                    .disabled(!canAct)
            } else {
                ProgressView().tint(.mint)
            }
        } else if draft != nil {
            draftRecovery
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40)).foregroundStyle(.mint)
            Text("Your next workout").font(.title3.bold())
            Text("Create and accept a workout in Gyma on iPhone to begin.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func setScreen(_ draft: WatchSetDraft, workout: Workout, compact: Bool, availableHeight: CGFloat) -> some View {
        let exercise = workout.exercises.first { $0.exerciseID == draft.exerciseID }
        let setTitle = exercise?.target.map { "SET \(draft.workingSetCount + 1) OF \($0.sets)" } ?? "SET \(draft.workingSetCount + 1)"
        if draft.phase != .review { eyebrow(setTitle) }
        Text(exerciseName(draft.exerciseID))
            .font(.system(size: draft.phase == .review ? 16 : (compact ? 19 : 22), weight: .bold, design: .rounded))
            .lineLimit(draft.phase == .review || compact ? 1 : 2).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
        switch draft.phase {
        case .prepared:
            preparationValues(draft)
            primaryButton("Start Set", symbol: "play.fill") {
                guard let snapshot = connectivity.snapshot else { return }
                change { try $0.start(snapshot: snapshot) }
            }
            .disabled(!canAct || !currentDraft)
        case .performing:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(draft.kg.formatted()).font(.system(size: compact ? 29 : 35, weight: .bold, design: .rounded))
                Text("kg").foregroundStyle(.secondary)
                Text("× \(draft.expectedReps)").font(.title2.bold()).foregroundStyle(.mint)
            }
            primaryButton("Finish Set", symbol: "checkmark") {
                guard let snapshot = connectivity.snapshot else { return }
                change { try $0.done(snapshot: snapshot) }
            }
            .disabled(!canAct || !currentDraft)
        case .review:
            WatchActualRepsPicker(title: "REPS · \(setTitle)",
                                 height: max(44, min(compact ? 56 : 66, availableHeight - 104)), reps: Binding(
                get: { local.flow.draft?.actualReps ?? draft.actualReps },
                set: { reps in change { try $0.setActual(kg: $0.draft?.actualKg ?? draft.actualKg, reps: reps) } }
            ))
            Button { editor = .actualKg } label: {
                HStack {
                    Text("Actual load")
                    Spacer()
                    Text("\(draft.actualKg.formatted()) kg").bold()
                    Image(systemName: "pencil").font(.caption2)
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(!canAct || !currentDraft)
            primaryButton("Confirm Set", symbol: "checkmark.circle.fill") { submitSet() }
                .disabled(!canAct || !currentDraft)
        case .submitting:
            Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                .font(.title2.bold()).foregroundStyle(.mint)
            ProgressView("Saving set…").font(.caption)
        }
    }

    private func preparationValues(_ draft: WatchSetDraft) -> some View {
        HStack(spacing: 8) {
            valueButton(draft.kg.formatted(), unit: "KG", field: .preparedKg)
            valueButton("\(draft.expectedReps)", unit: "REPS", field: .expectedReps)
        }
        .disabled(!canAct || !currentDraft)
    }

    private func valueButton(_ value: String, unit: String, field: WatchValueField) -> some View {
        Button { editor = field } label: {
            VStack(spacing: 2) {
                Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                HStack(spacing: 3) {
                    Text(unit).font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain).accessibilityLabel("Change \(unit): \(value)")
    }

    private func restScreen(_ timer: RestTimer, compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 5) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = restDisplayDate(timerID: timer.id, now: context.date)
                let remaining = Int(ceil(timer.remaining(at: date)))
                VStack(spacing: 3) {
                    eyebrow(remaining > 0 ? "REST" : "REST COMPLETE")
                    Text(remaining > 0 ? watchDuration(Double(remaining)) : "Ready")
                        .font(.system(size: compact ? 39 : 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.mint).minimumScaleFactor(0.65).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            if let draft, currentDraft {
                Text(exerciseName(draft.exerciseID)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 12) {
                    Button("\(draft.kg.formatted()) kg") { editor = .preparedKg }
                    Button("\(draft.expectedReps) reps") { editor = .expectedReps }
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(!canAct || draft.phase != .prepared)
            }
            primaryButton("Dismiss", symbol: "play.fill", subtitle: "Start next set") { dismissRest() }
                .disabled(!canAct || !currentDraft || draft?.phase != .prepared)
        }
    }

    private var draftRecovery: some View {
        VStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.orange)
            Text("Workout changed").font(.headline)
            if let draft {
                Text(exerciseName(draft.exerciseID))
                    .font(.caption).lineLimit(1)
                Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                    .font(.title3.bold())
            }
            primaryButton("Review draft", symbol: "exclamationmark.circle") { showSettings = true }
        }
    }

    @ViewBuilder
    private var compactStatus: some View {
        if let statusText {
            Button(statusText) { showSettings = true }
                .font(.caption2).buttonStyle(.plain).foregroundStyle(hasIssues ? Color.orange : Color.mint)
        }
    }

    private func primaryButton(_ title: String, symbol: String, subtitle: String? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Label(title, systemImage: symbol).font(.headline)
                if let subtitle { Text(subtitle).font(.caption2) }
            }
        }
        .buttonStyle(WatchPrimaryButtonStyle())
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2).foregroundStyle(.mint)
    }

    @ViewBuilder
    private func valueEditor(_ field: WatchValueField) -> some View {
        if let draft {
            WatchValueEditor(field: field, kg: field == .actualKg ? draft.actualKg : draft.kg,
                             reps: draft.expectedReps) { kg, reps in
                change {
                    if field == .actualKg { try $0.setActual(kg: kg, reps: $0.draft?.actualReps ?? draft.actualReps) }
                    else { try $0.setPreparation(kg: kg, reps: reps) }
                }
            }
        }
    }

    private func reconcile() {
        do {
            try local.update {
                $0.reconcile(snapshot: connectivity.snapshot, pending: connectivity.pendingCommand,
                             acknowledgement: connectivity.lastAcknowledgement)
            }
        } catch { localError = error.localizedDescription }
    }

    private func change(_ operation: (inout WatchSetFlow) throws -> Void) {
        do { try local.update(operation) }
        catch { localError = error.localizedDescription }
    }

    private func submitSet() {
        guard canAct, let snapshot = connectivity.snapshot else { return }
        do {
            let set = try local.update { try $0.prepareSubmission(snapshot: snapshot) }
            guard let draft = local.flow.draft else { return }
            do {
                try connectivity.submit(.logSet(exerciseID: draft.exerciseID, set: set),
                                        expectedWorkoutID: draft.workoutID, basedOnRevision: draft.completionRevision)
            } catch {
                try local.update { $0.submissionFailed() }
                throw error
            }
            if let command = connectivity.pendingCommand { try local.update { $0.markSubmitted(command) } }
        } catch { localError = error.localizedDescription }
    }

    private func dismissRest() {
        guard canAct, let snapshot = connectivity.snapshot, let timer = snapshot.restTimer else { return }
        do {
            try local.update { try $0.prepareRestResume(snapshot: snapshot) }
            do {
                try connectivity.submit(.skipRest(timerID: timer.id), expectedWorkoutID: timer.workoutID,
                                        basedOnRevision: snapshot.revision)
            } catch {
                try local.update { $0.restSubmissionFailed() }
                throw error
            }
            if let command = connectivity.pendingCommand { try local.update { $0.markRestSubmitted(command) } }
        } catch { localError = error.localizedDescription }
    }

    private func prepareFinish(_ workout: Workout) {
        finishWorkoutID = workout.id; finishRevision = connectivity.snapshot?.revision; confirmFinish = true
    }

    private func handleSettingsAction() {
        defer { settingsAction = nil }
        switch settingsAction {
        case .some(.finish):
            if let workout = connectivity.snapshot?.activeWorkout { prepareFinish(workout) }
        case .some(.discard): confirmDiscard = true
        case nil: break
        }
    }

    private func hasHiddenExercises(_ workout: Workout) -> Bool {
        if let total = connectivity.snapshot?.totalExerciseCount { return total > workout.exercises.count }
        return connectivity.snapshot?.isTruncated == true
    }

    private func restDisplayDate(timerID: String, now: Date) -> Date {
        if let pending = connectivity.pendingCommand, case let .skipRest(id) = pending.action, id == timerID {
            return pending.createdAt
        }
        return now
    }

    private func exerciseName(_ id: String) -> String {
        connectivity.snapshot?.catalog.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

@MainActor
private struct WatchActualRepsPicker: View {
    let title: String
    let height: CGFloat
    @Binding var reps: Int
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Picker("Reps completed", selection: $reps) {
                ForEach(1...100, id: \.self) { value in Text("\(value)").font(.title.bold()).tag(value) }
            }
            .pickerStyle(.wheel).labelsHidden().frame(height: height).focused($focused)
        }
        .onAppear { focused = true }
    }
}

private enum WatchValueField: String, Identifiable {
    case preparedKg, expectedReps, actualKg
    var id: String { rawValue }
    var title: String { self == .expectedReps ? "Expected reps" : (self == .actualKg ? "Actual kg" : "Set weight") }
}

private enum WatchSettingsAction { case finish, discard }

private struct WatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isEnabled ? Color.mint : Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(isEnabled ? Color.black : Color.gray)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

@MainActor
private struct WatchValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    let field: WatchValueField
    @State private var kg: Double
    @State private var reps: Int
    @FocusState private var focused: Bool
    let save: (Double, Int) -> Void

    init(field: WatchValueField, kg: Double, reps: Int, save: @escaping (Double, Int) -> Void) {
        self.field = field; _kg = State(initialValue: kg); _reps = State(initialValue: reps); self.save = save
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                if field == .expectedReps {
                    Picker("Expected reps", selection: $reps) {
                        ForEach(1...100, id: \.self) { value in Text("\(value) reps").tag(value) }
                    }
                    .pickerStyle(.wheel).focused($focused)
                } else {
                    Picker("Kilograms", selection: $kg) {
                        if kg.truncatingRemainder(dividingBy: 0.5) != 0 { Text("\(kg.formatted()) kg").tag(kg) }
                        ForEach(0...2000, id: \.self) { value in
                            Text("\((Double(value) / 2).formatted()) kg").tag(Double(value) / 2)
                        }
                    }
                    .pickerStyle(.wheel).focused($focused)
                }
                Button("Use value") { save(kg, reps); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.mint)
            }
            .navigationTitle(field.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}

@MainActor
private struct WatchWorkoutSettings: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @EnvironmentObject private var runtime: WatchWorkoutRuntime
    let storageError: String?
    let draft: WatchSetDraft?
    let isDraftCurrent: Bool
    let discardDraft: () -> Void
    let finishWorkout: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let draft, !isDraftCurrent, draft.phase != .submitting {
                    Section("Saved Watch draft") {
                        Text(connectivity.snapshot?.catalog.first { $0.id == draft.exerciseID }?.name ?? draft.exerciseID)
                            .font(.headline)
                        Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                        Text("This draft no longer matches the current workout. Review your workout on iPhone before discarding it.")
                            .font(.caption2)
                        Button("Use current workout", action: discardDraft)
                            .disabled(connectivity.pendingCommand != nil || connectivity.snapshot == nil || storageError != nil)
                    }
                }
                if let pending = connectivity.pendingCommand {
                    Section("Saved change") {
                        Text(pending.action.watchDescription).font(.headline)
                        Text("Saved on this Watch, waiting for iPhone confirmation. Open Gyma on iPhone if this takes a while.")
                            .font(.caption2)
                        if case let .logSet(_, set) = pending.action {
                            Text("\(set.kg.formatted()) kg × \(set.reps)")
                        }
                    }
                }
                if let receipt = connectivity.lastAcknowledgement, receipt.status == .rejected {
                    Section("Change not saved") {
                        Text(receipt.message ?? "Review the current workout before retrying. Your draft is preserved.")
                            .font(.caption2).foregroundStyle(.orange)
                        if let command = connectivity.rejectedCommand, case let .logSet(_, set) = command.action {
                            Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)")
                        }
                    }
                }
                if let command = connectivity.quarantinedCommand {
                    Section("Earlier change needs review") {
                        Text("This change was not applied after your iPhone data changed. Review the earlier workout on iPhone.")
                            .font(.caption2).foregroundStyle(.orange)
                        if case let .logSet(_, set) = command.action {
                            Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)")
                        }
                    }
                }
                if let error = storageError ?? connectivity.lastError {
                    Section("Action needed") { Text(error).font(.caption2).foregroundStyle(.orange) }
                }
                Section("Rest alerts") {
                    Toggle("Rest vibration", isOn: Binding(
                        get: { notifications.enabled },
                        set: { value in Task { await notifications.setEnabled(value) } }
                    ))
                    Button("Test vibration") { notifications.testHaptic() }
                    if let message = notifications.message {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                    }
                    if let message = runtime.message {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                    }
                }
                if connectivity.snapshot?.activeWorkout != nil {
                    Button("Finish workout early", role: .destructive, action: finishWorkout)
                        .disabled(!connectivity.canSubmit)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

@MainActor
private final class WatchSetFlowStore: ObservableObject {
    @Published private(set) var flow = WatchSetFlow()
    @Published private(set) var storageError: String?
    private let url: URL
    private var unreadable = false

    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GymaConnectivity", isDirectory: true)
            .appendingPathComponent("watch-set-flow.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count < 64 * 1024 else { throw GymaError.invalid("Saved Watch set is too large.") }
                flow = try JSONDecoder().decode(WatchSetFlow.self, from: data)
                try flow.validate()
            }
        } catch {
            unreadable = true
            storageError = "Your saved set could not be read. Reopen Gyma to retry; the draft is preserved."
        }
    }

    @discardableResult
    func update<T>(_ operation: (inout WatchSetFlow) throws -> T) throws -> T {
        guard !unreadable else { throw GymaError.invalid(storageError ?? "Watch storage is unavailable.") }
        var next = flow
        let result = try operation(&next)
        try next.validate()
        guard next != flow else { return result }
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            flow = next; storageError = nil
            return result
        } catch {
            storageError = "Your set could not be saved on this Watch. Free some storage and reopen Gyma."
            throw error
        }
    }
}

private func watchDuration(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, min(86400, seconds)))
    return String(format: "%d:%02d", value / 60, value % 60)
}

private extension WatchAction {
    var watchDescription: String {
        switch self {
        case .logSet: return "Saving set…"
        case .skipRest: return "Starting next set…"
        case .extendRest: return "Updating rest…"
        case .finishWorkout: return "Finishing workout…"
        }
    }
}
