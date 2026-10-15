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
                return AnyView(WatchDraftRecoveryView(draft: draft, exerciseName: exerciseName(draft.exerciseID),
                                                     reviewDraft: { showSettings = true }))
            } else if showExerciseMenu {
                return AnyView(exerciseMenu(workout))
            } else if let timer = restTimer, timer.workoutID == workout.id {
                return AnyView(WatchRestScreen(
                    timer: timer, compact: compact, pausedAt: pendingRestDate(timerID: timer.id),
                    draft: currentDraft ? draft : nil, exerciseName: draft.map { exerciseName($0.exerciseID) },
                    canEditPreparation: canAct && draft?.phase == .prepared,
                    canDismissRest: canAct && currentDraft && draft?.phase == .prepared,
                    chooseSetType: { chooseSetType = true }, editValue: { editor = $0 }, dismissRest: dismissRest
                ))
            } else if let draft {
                return AnyView(setScreen(draft, workout: workout, compact: compact, availableHeight: availableHeight))
            } else if hasHiddenExercises(workout) {
                return AnyView(Text("Continue on iPhone to see the remaining exercises.").font(.headline))
            } else if workout.nextExercise == nil {
                return AnyView(Group {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.mint)
                    Text("Workout complete").font(.title3.bold())
                    WatchWorkoutButton("Finish workout", symbol: "checkmark") { prepareFinish(workout) }
                        .disabled(!canAct)
                })
            } else {
                return AnyView(ProgressView().tint(.mint))
            }
        } else if draft != nil {
            return AnyView(WatchDraftRecoveryView(draft: draft, exerciseName: draft.map { exerciseName($0.exerciseID) },
                                                 reviewDraft: { showSettings = true }))
        } else {
            return AnyView(WatchReadyWorkoutView(
                snapshot: connectivity.snapshot, hasStorageError: local.storageError != nil,
                canStartPlan: { connectivity.canStartAcceptedPlan($0, at: $1) },
                start: prepareReadyWorkout, refresh: connectivity.refresh
            ))
        }
    }

    private func exerciseMenu(_ workout: Workout) -> some View {
        WatchExerciseMenu(
            workout: workout, draft: draft, pendingCommand: connectivity.pendingCommand ?? pendingExerciseChange,
            restTimer: restTimer, showsRest: connectivity.pendingCommand == nil,
            hasHiddenExercises: hasHiddenExercises(workout), canCancelSet: canAct && currentDraft,
            canFinishWorkout: canAct, exerciseName: exerciseName, canChooseExercise: canChooseExercise,
            selectExercise: selectExercise, resumeSet: { showExerciseMenu = false },
            cancelSet: { prepareSetChange(.cancel) }, finishWorkout: { prepareFinish(workout) }
        )
    }

    private func setScreen(_ draft: WatchSetDraft, workout: Workout, compact: Bool, availableHeight: CGFloat) -> some View {
        WatchSetScreen(
            draft: draft, exercise: workout.exercises.first { $0.exerciseID == draft.exerciseID },
            exerciseName: exerciseName(draft.exerciseID), compact: compact, availableHeight: availableHeight,
            isEnabled: canAct && currentDraft,
            actualReps: Binding(
                get: { local.flow.draft?.actualReps ?? draft.actualReps },
                set: { reps in change { try $0.setActual(kg: $0.draft?.actualKg ?? draft.actualKg, reps: reps) } }
            ),
            actualKg: Binding(
                get: { local.flow.draft?.actualKg ?? draft.actualKg },
                set: { kg in change { try $0.setActual(kg: kg, reps: $0.draft?.actualReps ?? draft.actualReps) } }
            ),
            chooseSetType: { chooseSetType = true }, editValue: { editor = $0 },
            startSet: {
                guard let snapshot = connectivity.snapshot else { return }
                change { try $0.start(snapshot: snapshot) }
            },
            finishSet: {
                guard let snapshot = connectivity.snapshot else { return }
                change { try $0.done(snapshot: snapshot) }
            },
            confirmReps: { change { try $0.confirmReps() } },
            confirmWeight: confirmWeight, confirmEffort: confirmEffort
        )
    }

    private func canChooseExercise(_ exercise: WorkoutExercise) -> Bool {
        guard !exercise.isTargetResolved, canAct else { return false }
        guard let draft, draft.phase != .prepared else { return true }
        return draft.phase != .submitting && draft.exerciseID == exercise.exerciseID
    }

    @ViewBuilder
    private var compactStatus: some View {
        if let statusText {
            Button(statusText) { showSettings = true }
                .font(.caption2).buttonStyle(.plain).foregroundStyle(hasIssues ? Color.orange : Color.mint)
        }
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

    private func confirmEffort(_ effort: SetEffort?) {
        guard canAct, currentDraft else { return }
        do {
            try local.update { try $0.confirmEffort(effort) }
            submitSet()
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

    private func prepareReadyWorkout(_ context: WatchReadyContext) {
        guard connectivity.canStartAcceptedPlan(context.plan.id) else {
            localError = "This workout is no longer ready for today. Review it in Gyma on iPhone."
            return
        }
        readyContext = context
    }

    private func pendingRestDate(timerID: String) -> Date? {
        if let pending = connectivity.pendingCommand, case let .skipRest(id) = pending.action, id == timerID {
            return pending.createdAt
        }
        return nil
    }

    private func exerciseName(_ id: String) -> String {
        connectivity.snapshot?.catalog.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
