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
    @State private var chooseSetType = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var finishWorkoutID: String?
    @State private var finishRevision: Int?
    @State private var localError: String?
    @State private var settingsAction: WatchSettingsAction?
    @State private var readyContext: WatchReadyContext?
    @State private var showExerciseMenu = true
    @State private var requestedExerciseID: String?
    @State private var setChange: WatchSetChangeRequest?

    private var draft: WatchSetDraft? { local.flow.draft }
    private var canAct: Bool {
        connectivity.canSubmit && local.storageError == nil && local.flow.pendingWorkoutChange == nil
    }
    private var currentDraft: Bool {
        connectivity.snapshot.map { draft?.matches($0) == true } ?? false
    }
    private var pendingExerciseChange: WatchCommand? {
        guard let command = local.flow.pendingWorkoutChange,
              command.storeID == connectivity.snapshot?.storeID,
              command.workoutID == connectivity.snapshot?.activeWorkout?.id else { return nil }
        return command
    }
    private var restTimer: RestTimer? {
        connectivity.snapshot?.restTimer ?? local.flow.resumeRestTimer
    }
    private var hasIssues: Bool {
        local.storageError != nil || connectivity.lastError != nil ||
        connectivity.lastAcknowledgement?.status == .rejected || connectivity.quarantinedCommand != nil ||
        runtime.message != nil || notifications.message != nil ||
        (draft != nil && !currentDraft && draft?.phase != .submitting && pendingExerciseChange == nil)
    }
    private var statusText: String? {
        if local.storageError != nil || connectivity.lastAcknowledgement?.status == .rejected { return "Change not saved" }
        if connectivity.quarantinedCommand != nil || connectivity.lastError != nil ||
            (restTimer != nil && draft != nil && !currentDraft && draft?.phase != .submitting && pendingExerciseChange == nil) {
            return "Review saved change"
        }
        if let pending = connectivity.pendingCommand ?? pendingExerciseChange, draft?.phase != .submitting {
            return pending.action.watchDescription
        }
        return nil
    }
    private var navigationTitle: String {
        if showExerciseMenu, connectivity.snapshot?.activeWorkout != nil { return "Exercises" }
        guard draft?.phase == .review else { return "Gyma" }
        switch draft?.currentReviewStep {
        case .weight: return "Weight"
        case .effort: return "Effort"
        default: return "Reps"
        }
    }

    var body: some View {
        NavigationStack {
            workoutPresentation
        }
    }

    // Opaque computed properties still compose one concrete generic view type.
    // Erase each root layer so the Watch does not materialize that entire type
    // while opening the app. Keep one navigation and presentation host.
    private var workoutLayout: AnyView {
        AnyView(GeometryReader { geometry in
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
        .navigationTitle(navigationTitle)
        .toolbar { workoutToolbar })
    }

    @ToolbarContentBuilder
    private var workoutToolbar: some ToolbarContent {
        if !showExerciseMenu, draft?.phase == .review && draft?.currentReviewStep != .reps {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    change { flow in
                        if flow.draft?.currentReviewStep == .effort { try flow.backToWeight() }
                        else { try flow.backToReps() }
                    }
                } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(draft?.currentReviewStep == .effort ? "Back to weight" : "Back to reps")
                .disabled(!canAct || !currentDraft)
            }
        } else if !showExerciseMenu, connectivity.snapshot?.activeWorkout != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button { showExerciseMenu = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Choose an exercise")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: connectivity.snapshot?.activeWorkout == nil ? "gearshape" : "ellipsis")
                    .overlay(alignment: .topTrailing) {
                        if hasIssues || connectivity.pendingCommand != nil {
                            Circle().fill(hasIssues ? Color.orange : Color.mint).frame(width: 6, height: 6)
                        }
                    }
            }
            .accessibilityLabel(hasIssues ? "Workout options, action needed" : "Set and workout options")
        }
    }

    private var workoutSheets: AnyView {
        AnyView(workoutLayout
            .sheet(item: $editor) { field in valueEditor(field) }
            .sheet(item: $readyContext) { context in
                WatchReadinessView(context: context)
            }
            .sheet(isPresented: $showSettings, onDismiss: handleSettingsAction) {
                WatchWorkoutSettings(storageError: local.storageError, draft: draft, isDraftCurrent: currentDraft,
                                     canChangeWorkout: canAct,
                                     discardDraft: { settingsAction = .discard; showSettings = false },
                                     finishWorkout: { settingsAction = .finish; showSettings = false },
                                     chooseExercise: { settingsAction = .exercises; showSettings = false },
                                     cancelSet: { settingsAction = .cancelSet; showSettings = false },
                                     skipSet: { settingsAction = .skipSet; showSettings = false },
                                     skipExercise: { settingsAction = .skipExercise; showSettings = false })
            })
    }

    private var observedWorkout: AnyView {
        AnyView(workoutSheets
            .task { reconcile() }
            .onChange(of: connectivity.snapshot) { _, _ in reconcile() }
            .onChange(of: connectivity.pendingCommand) { _, _ in reconcile() }
            .onChange(of: connectivity.lastAcknowledgement) { _, _ in reconcile() }
            .onChange(of: draft?.workingSetCount) { _, _ in editor = nil }
            .onChange(of: draft?.exerciseID) { _, _ in editor = nil }
            .onChange(of: draft?.position) { _, _ in editor = nil; chooseSetType = false }
            .onChange(of: connectivity.snapshot?.activeWorkout?.id) { _, _ in
                showExerciseMenu = true; requestedExerciseID = nil
            })
    }

    private var workoutFinishDialogs: AnyView {
        AnyView(observedWorkout
            .confirmationDialog("Set type", isPresented: $chooseSetType, titleVisibility: .visible) {
                Button("Working set") { selectSetType(isWarmup: false) }
                Button("Warm-up") { selectSetType(isWarmup: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Warm-ups do not count toward the working-set target.") }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish workout", role: .destructive) {
                    do {
                        try connectivity.submit(.finishWorkout, expectedWorkoutID: finishWorkoutID,
                                                basedOnRevision: finishRevision)
                    } catch { localError = error.localizedDescription }
                }
                Button("Keep training", role: .cancel) {}
            } message: { Text("Your confirmed sets will be saved on iPhone.") })
    }

    private var workoutPresentation: AnyView {
        AnyView(workoutFinishDialogs
            .confirmationDialog("Discard this saved draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) {
                    guard let snapshot = connectivity.snapshot else { return }
                    change { $0.useCurrentWorkout(snapshot) }
                    showExerciseMenu = true
                }
                Button("Keep draft", role: .cancel) {}
            } message: { Text("Only this unsent Watch draft will be removed. Your confirmed sets stay saved.") }
            .confirmationDialog(setChange?.kind.title ?? "Change set", isPresented: showsSetChange,
                                titleVisibility: .visible, presenting: setChange) { request in
                Button(request.kind.buttonTitle, role: .destructive) { applySetChange(request) }
                Button("Keep training", role: .cancel) {}
            } message: { request in Text(request.kind.message) }
            .alert("Could not save the change", isPresented: showsLocalError) {
                Button("OK", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") })
    }

    private var showsSetChange: Binding<Bool> {
        Binding(get: { setChange != nil }, set: { if !$0 { setChange = nil } })
    }

    private var showsLocalError: Binding<Bool> {
        Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })
    }

    private func focusedWorkout(compact: Bool, availableHeight: CGFloat) -> AnyView {
        if let pending = connectivity.pendingCommand, case .startAcceptedPlan = pending.action {
            return AnyView(Group {
                ProgressView().tint(.mint)
                Text("Starting workout…").font(.headline)
                Text("Waiting for iPhone confirmation")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            })
        } else if let workout = connectivity.snapshot?.activeWorkout {
            if pendingExerciseChange != nil {
                return AnyView(exerciseMenu(workout))
            } else if let draft, !currentDraft && draft.phase != .submitting {
                return AnyView(draftRecovery)
            } else if showExerciseMenu {
                return AnyView(exerciseMenu(workout))
            } else if let timer = restTimer, timer.workoutID == workout.id {
                return AnyView(restScreen(timer, compact: compact))
            } else if let draft {
                return AnyView(setScreen(draft, workout: workout, compact: compact, availableHeight: availableHeight))
            } else if hasHiddenExercises(workout) {
                return AnyView(Text("Continue on iPhone to see the remaining exercises.").font(.headline))
            } else if workout.nextExercise == nil {
                return AnyView(Group {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.mint)
                    Text("Workout complete").font(.title3.bold())
                    primaryButton("Finish workout", symbol: "checkmark") { prepareFinish(workout) }
                        .disabled(!canAct)
                })
            } else {
                return AnyView(ProgressView().tint(.mint))
            }
        } else if draft != nil {
            return AnyView(draftRecovery)
        } else {
            return AnyView(readyWorkout)
        }
    }

    private func exerciseMenu(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let pending = connectivity.pendingCommand ?? pendingExerciseChange {
                    Label(pending.action.watchDescription, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.mint)
                } else if let draft, draft.phase == .performing || draft.phase == .review {
                    Text("Resume or cancel your unsaved set before choosing another exercise.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(draft.phase == .review ? "Review current set" : "Resume current set") {
                        showExerciseMenu = false
                    }
                    .buttonStyle(WatchPrimaryButtonStyle())
                    Button("Cancel set", role: .destructive) { prepareSetChange(.cancel) }
                        .font(.caption).disabled(!canAct || !currentDraft)
                } else if workout.nextExercise != nil {
                    Text("Choose any exercise; return to the others later.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("All planned sets are done or skipped.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let timer = restTimer, timer.workoutID == workout.id, connectivity.pendingCommand == nil {
                    Button { showExerciseMenu = false } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = timer.remaining(at: context.date)
                            Label(remaining > 0 ? "Rest \(watchDuration(ceil(remaining)))" : "Rest complete",
                                  systemImage: "timer")
                                .font(.caption).foregroundStyle(.mint)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Choosing another exercise ends this rest.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(workout.exercises) { exercise in
                    Button { selectExercise(exercise) } label: {
                        HStack(spacing: 7) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exerciseName(exercise.exerciseID)).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(exerciseProgress(exercise)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: exercise.isTargetResolved ?
                                  (exercise.skippedSetCount > 0 || exercise.skippedRemainingAt != nil ? "minus.circle" : "checkmark.circle.fill") : "chevron.right")
                                .foregroundStyle(exercise.isTargetResolved ? Color.secondary : Color.mint)
                        }
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChooseExercise(exercise))
                    .accessibilityHint(exercise.isTargetResolved ? "No planned sets remaining" : "Choose this exercise")
                }
                if hasHiddenExercises(workout) {
                    Text("More exercises are available on iPhone.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Button(workout.nextExercise == nil && !hasHiddenExercises(workout) ? "Finish workout" : "Finish workout early") {
                    prepareFinish(workout)
                }
                .font(.caption).frame(maxWidth: .infinity).disabled(!canAct)
            }
            .padding(.vertical, 3)
        }
    }

    private func exerciseProgress(_ exercise: WorkoutExercise) -> String {
        let completed = exercise.target.map { "\(exercise.workingSetCount)/\($0.sets) done" }
            ?? "\(exercise.workingSetCount) sets done"
        if exercise.skippedSetCount > 0 { return completed + " · \(exercise.skippedSetCount) skipped" }
        return completed + (exercise.skippedRemainingAt != nil ? " · stopped" : "")
    }

    private func canChooseExercise(_ exercise: WorkoutExercise) -> Bool {
        guard !exercise.isTargetResolved, canAct else { return false }
        guard let draft, draft.phase != .prepared else { return true }
        return draft.phase != .submitting && draft.exerciseID == exercise.exerciseID
    }

    private var readyWorkout: some View {
        // Re-evaluate absolute availability and the Watch's local day even if no
        // new phone snapshot arrives at midnight or after a time-zone change.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                if let snapshot = connectivity.snapshot, let plan = snapshot.readyPlan,
                   plan.isAvailable(at: context.date), Calendar.current.isDate(plan.scheduledFor, inSameDayAs: context.date) {
                    eyebrow("TODAY")
                    Text(plan.title).font(.system(size: 23, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
                    primaryButton("Start Workout", symbol: "play.fill") {
                        guard connectivity.canStartAcceptedPlan(plan.id) else {
                            localError = "This workout is no longer ready for today. Review it in Gyma on iPhone."
                            return
                        }
                        readyContext = WatchReadyContext(storeID: snapshot.storeID, revision: snapshot.revision, plan: plan)
                    }
                    .disabled(!connectivity.canStartAcceptedPlan(plan.id, at: context.date) || local.storageError != nil)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 36)).foregroundStyle(.mint)
                    Text("No workout ready").font(.headline)
                    Text("Save your program and training calendar in Gyma on iPhone, or accept a workout for today.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in connectivity.refresh() }
        }
    }

    @ViewBuilder
    private func setScreen(_ draft: WatchSetDraft, workout: Workout, compact: Bool, availableHeight: CGFloat) -> some View {
        let exercise = workout.exercises.first { $0.exerciseID == draft.exerciseID }
        let setTitle = draft.isWarmupSet ? "WARM-UP" :
            (exercise?.target.map { "SET \((exercise?.resolvedSetCount ?? draft.workingSetCount) + 1) OF \($0.sets)" } ?? "SET \(draft.workingSetCount + 1)")
        if draft.phase == .prepared {
            Button { chooseSetType = true } label: {
                HStack(spacing: 4) {
                    eyebrow(setTitle)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.mint)
                }
            }
            .buttonStyle(.plain).disabled(!canAct || !currentDraft)
            .accessibilityLabel(draft.isWarmupSet ? "Warm-up, change set type" : "Working set, change set type")
        } else if draft.phase != .review || draft.currentReviewStep == .weight { eyebrow(setTitle) }
        Text(exerciseName(draft.exerciseID))
            .font(.system(size: draft.phase == .review ? 16 : (compact ? 19 : 22), weight: .bold, design: .rounded))
            .lineLimit(draft.phase == .review || compact ? 1 : 2).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
        if (draft.phase == .prepared || draft.phase == .performing), !draft.isWarmupSet,
           let effort = exercise?.target?.targetEffort {
            Text("Aim: \(effort.label)").font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
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
            if draft.currentReviewStep == .reps {
                WatchRepsControl(title: "REPS · \(setTitle)",
                                 height: max(50, min(72, availableHeight - 86)), reps: Binding(
                    get: { local.flow.draft?.actualReps ?? draft.actualReps },
                    set: { reps in change { try $0.setActual(kg: $0.draft?.actualKg ?? draft.actualKg, reps: reps) } }
                ))
                .disabled(!canAct || !currentDraft)
                primaryButton("Confirm Reps", symbol: "arrow.right") {
                    change { try $0.confirmReps() }
                }
                .disabled(!canAct || !currentDraft)
            } else if draft.currentReviewStep == .weight {
                WatchWeightReview(height: max(44, min(94, availableHeight - 108)), kg: Binding(
                    get: { local.flow.draft?.actualKg ?? draft.actualKg },
                    set: { kg in change { try $0.setActual(kg: kg, reps: $0.draft?.actualReps ?? draft.actualReps) } }
                ), isEnabled: canAct && currentDraft, confirm: confirmWeight)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SetEffort.allCases) { effort in
                            effortButton(effort.label, effort: effort)
                        }
                        effortButton("Not sure", effort: nil)
                    }
                }
                .frame(maxHeight: max(100, availableHeight - 30))
            }
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
                    Button(draft.isWarmupSet ? "Warm-up" : "Working") { chooseSetType = true }
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
            WatchValueEditor(field: field, kg: draft.kg,
                             reps: draft.expectedReps) { kg, reps in
                guard canAct, let snapshot = connectivity.snapshot, draft.matches(snapshot) else {
                    throw GymaError.stale("The workout changed. Reopen the current set to edit it.")
                }
                try local.update { try $0.setPreparation(kg: kg, reps: reps) }
            }
        }
    }

    private func reconcile() {
        do {
            let previousExerciseID = draft?.exerciseID
            try local.update {
                $0.reconcile(snapshot: connectivity.snapshot, pending: connectivity.pendingCommand,
                             acknowledgement: connectivity.lastAcknowledgement)
            }
            if let requestedExerciseID, draft?.exerciseID == requestedExerciseID, currentDraft,
               connectivity.pendingCommand == nil, canAct {
                self.requestedExerciseID = nil
                showExerciseMenu = false
            } else if previousExerciseID != draft?.exerciseID {
                showExerciseMenu = true
            }
            if connectivity.pendingCommand == nil, connectivity.lastAcknowledgement?.status == .rejected {
                requestedExerciseID = nil
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

    private func confirmWeight(_ kg: Double) {
        guard canAct, currentDraft else { return }
        do {
            try local.update { flow in
                guard let draft = flow.draft else { return }
                try flow.setActual(kg: kg, reps: draft.actualReps)
                try flow.confirmWeight()
            }
            if local.flow.draft?.isWarmupSet == true { submitSet() }
        } catch { localError = error.localizedDescription }
    }

    private func selectSetType(isWarmup: Bool) {
        guard canAct, currentDraft else { return }
        change { try $0.setWarmup(isWarmup) }
    }

    private func selectExercise(_ exercise: WorkoutExercise) {
        guard canChooseExercise(exercise), let snapshot = connectivity.snapshot,
              let workout = snapshot.activeWorkout else { return }
        if draft?.exerciseID == exercise.exerciseID, currentDraft {
            showExerciseMenu = false
            return
        }
        do {
            requestedExerciseID = exercise.exerciseID
            try connectivity.submit(.selectExercise(exerciseID: exercise.exerciseID),
                                    expectedWorkoutID: workout.id, basedOnRevision: snapshot.revision,
                                    expectedStoreID: snapshot.storeID)
            if let command = connectivity.pendingCommand {
                try local.update { $0.markWorkoutChangeSubmitted(command) }
            }
        } catch {
            if connectivity.pendingCommand == nil { requestedExerciseID = nil }
            localError = error.localizedDescription
        }
    }

    private func prepareSetChange(_ kind: WatchSetChangeKind) {
        guard canAct, currentDraft, let draft, draft.phase != .submitting,
              let snapshot = connectivity.snapshot else { return }
        setChange = WatchSetChangeRequest(kind: kind, storeID: snapshot.storeID,
                                         workoutID: draft.workoutID, exerciseID: draft.exerciseID,
                                         revision: snapshot.revision)
    }

    private func applySetChange(_ request: WatchSetChangeRequest) {
        guard canAct, let snapshot = connectivity.snapshot else { return }
        do {
            guard snapshot.storeID == request.storeID, snapshot.activeWorkout?.id == request.workoutID,
                  draft?.exerciseID == request.exerciseID, currentDraft else {
                throw GymaError.stale("The workout changed. Review your current set before trying again.")
            }
            if request.kind == .cancel {
                try local.update { try $0.cancelSet(snapshot: snapshot) }
            } else {
                let action: WatchAction = request.kind == .skipSet ? .skipSet(exerciseID: request.exerciseID) :
                    .skipExercise(exerciseID: request.exerciseID)
                try connectivity.submit(action, expectedWorkoutID: request.workoutID,
                                        basedOnRevision: request.revision, expectedStoreID: request.storeID)
                if let command = connectivity.pendingCommand {
                    try local.update { $0.markWorkoutChangeSubmitted(command) }
                }
            }
            requestedExerciseID = nil
            showExerciseMenu = true
        } catch { localError = error.localizedDescription }
    }

    private func effortButton(_ title: String, effort: SetEffort?) -> some View {
        Button {
            guard canAct, currentDraft else { return }
            do {
                try local.update { try $0.confirmEffort(effort) }
                submitSet()
            } catch { localError = error.localizedDescription }
        } label: {
            Text(title).font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!canAct || !currentDraft)
        .accessibilityHint("Save this working set")
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
        case .some(.exercises): showExerciseMenu = true
        case .some(.cancelSet): prepareSetChange(.cancel)
        case .some(.skipSet): prepareSetChange(.skipSet)
        case .some(.skipExercise): prepareSetChange(.skipExercise)
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

private enum WatchSettingsAction { case finish, discard, exercises, cancelSet, skipSet, skipExercise }

private struct WatchSetChangeRequest {
    let kind: WatchSetChangeKind
    let storeID: String
    let workoutID: String
    let exerciseID: String
    let revision: Int
}

private enum WatchSetChangeKind: Equatable {
    case cancel, skipSet, skipExercise

    var title: String {
        switch self {
        case .cancel: return "Cancel this set?"
        case .skipSet: return "Skip this planned set?"
        case .skipExercise: return "Stop this exercise?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .cancel: return "Cancel set"
        case .skipSet: return "Skip set"
        case .skipExercise: return "Skip remaining sets"
        }
    }

    var message: String {
        switch self {
        case .cancel: return "Remove this unsaved set and return to the exercise menu. Nothing will be logged; the planned set stays available."
        case .skipSet: return "This set will be marked skipped, not completed. Any unsaved reps will be discarded."
        case .skipExercise: return "The remaining sets will be marked skipped, not completed. Any unsaved reps will be discarded. Your earlier completed sets stay saved."
        }
    }
}

private func watchDuration(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, min(86400, seconds)))
    return String(format: "%d:%02d", value / 60, value % 60)
}
