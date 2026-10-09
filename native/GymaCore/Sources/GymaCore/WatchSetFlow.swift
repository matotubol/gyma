import Foundation

public enum WatchSetPhase: String, Codable, Sendable {
    case prepared, performing, review, submitting
}

public enum WatchSetReviewStep: String, Codable, Sendable {
    case reps, weight
}

/// A local set is tied to a position in the confirmed workout, not a revision.
/// Unrelated phone edits may change the revision while a person is lifting.
public struct WatchSetDraft: Codable, Sendable, Equatable {
    public var storeID: String
    public var workoutID: String
    public var exerciseID: String
    public var workingSetCount: Int
    public var phase: WatchSetPhase = .prepared
    public var kg: Double
    public var expectedReps: Int
    public var actualKg: Double
    public var actualReps: Int
    /// Optional for drafts saved before review was split into two screens.
    public var reviewStep: WatchSetReviewStep?
    public var currentReviewStep: WatchSetReviewStep { reviewStep ?? .reps }
    public var setID: String?
    public var commandID: String?
    public var completionRevision: Int?

    public init(snapshot: CompanionSnapshot, workout: Workout, exercise: WorkoutExercise,
                kg: Double? = nil, expectedReps: Int? = nil) {
        storeID = snapshot.storeID; workoutID = workout.id; exerciseID = exercise.exerciseID
        workingSetCount = exercise.workingSetCount
        let recent = exercise.sets.last { $0.isWarmup == false }
        self.kg = min(1000, max(0, kg ?? recent?.kg ?? exercise.target?.loadKg ?? 0))
        self.expectedReps = min(100, max(1, expectedReps ?? exercise.target?.repsMin ?? recent?.reps ?? 8))
        actualKg = self.kg; actualReps = self.expectedReps; reviewStep = .reps
    }

    public func matches(_ snapshot: CompanionSnapshot) -> Bool {
        guard snapshot.storeID == storeID, let workout = snapshot.activeWorkout, workout.id == workoutID,
              let next = workout.nextExercise else { return false }
        return next.exerciseID == exerciseID && next.workingSetCount == workingSetCount
    }
}

/// Persist this value before submitting commands. The connectivity journal owns
/// delivery; this state owns the user's editable set and the intended rest exit.
public struct WatchSetFlow: Codable, Sendable, Equatable {
    public private(set) var draft: WatchSetDraft?
    public private(set) var resumeRestTimer: RestTimer?
    public private(set) var resumeCommandID: String?

    public init() {}

    public func validate() throws {
        if let draft {
            guard [draft.storeID, draft.workoutID, draft.exerciseID].allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
                  (0...1_000_000).contains(draft.workingSetCount),
                  draft.completionRevision.map({ (0...1_000_000_000).contains($0) }) ?? true,
                  [draft.setID, draft.commandID].allSatisfy({ $0.map { !$0.isEmpty && $0.count <= 200 } ?? true }) else {
                throw GymaError.invalid("Saved Watch set identity is invalid.")
            }
            try validateValues(kg: draft.kg, reps: draft.expectedReps)
            try validateValues(kg: draft.actualKg, reps: draft.actualReps)
        }
        if resumeCommandID != nil && resumeRestTimer == nil {
            throw GymaError.invalid("Saved Watch rest is incomplete.")
        }
    }

    public mutating func reconcile(snapshot: CompanionSnapshot?, pending: WatchCommand?,
                                   acknowledgement: CommandAcknowledgement?) {
        guard let snapshot else { return }

        // A crash between the connectivity journal write and our next write is
        // recovered from the durable command, including the exact completed set.
        if let pending, pending.storeID == snapshot.storeID {
            switch pending.action {
            case .logSet(let exerciseID, let set):
                if draft?.workoutID == pending.workoutID && draft?.exerciseID == exerciseID {
                    draft?.phase = .submitting; draft?.setID = set.id; draft?.commandID = pending.id
                    draft?.reviewStep = .weight
                    draft?.actualKg = set.kg; draft?.actualReps = set.reps
                } else if draft == nil, let workout = snapshot.activeWorkout,
                          workout.id == pending.workoutID,
                          let exercise = workout.exercises.first(where: { $0.exerciseID == exerciseID }) {
                    draft = WatchSetDraft(snapshot: snapshot, workout: workout, exercise: exercise)
                    let alreadyCounted = set.isWarmup == false && exercise.sets.contains(where: { $0.id == set.id })
                    draft?.workingSetCount = max(0, exercise.workingSetCount - (alreadyCounted ? 1 : 0))
                    draft?.phase = .submitting; draft?.setID = set.id; draft?.commandID = pending.id
                    draft?.reviewStep = .weight
                    draft?.actualKg = set.kg; draft?.actualReps = set.reps
                }
            case .skipRest(let timerID):
                if resumeRestTimer?.id == timerID { resumeCommandID = pending.id }
            default: break
            }
        }

        if let current = draft, current.phase == .submitting {
            if current.commandID == nil || pending?.id != current.commandID {
                if let acknowledgement, acknowledgement.commandID == current.commandID {
                    if acknowledgement.wasApplied { advance(snapshot) }
                    else {
                        draft?.phase = .review; draft?.commandID = nil; draft?.completionRevision = nil
                        draft?.reviewStep = .weight
                    }
                } else if containsSubmittedSet(snapshot, draft: current) {
                    advance(snapshot)
                } else {
                    // The draft was persisted before submit, but submit never
                    // reached the durable outbox. Keep the completed values.
                    draft?.phase = .review; draft?.commandID = nil; draft?.completionRevision = nil
                    draft?.reviewStep = .weight
                }
            }
        } else if let current = draft, containsSubmittedSet(snapshot, draft: current) {
            advance(snapshot)
        }

        if draft == nil { advance(snapshot) }

        if let commandID = resumeCommandID, pending?.id != commandID,
           let acknowledgement, acknowledgement.commandID == commandID {
            if acknowledgement.wasApplied, snapshot.restTimer == nil, draft?.matches(snapshot) == true {
                draft?.phase = .performing
            }
            resumeCommandID = nil; resumeRestTimer = nil
        } else if resumeCommandID == nil && pending == nil && snapshot.restTimer == nil {
            // No receipt proves that a queued rest exit was accepted. Do not
            // silently start a set after an interrupted or rejected operation.
            resumeRestTimer = nil
        }
    }

    public mutating func setPreparation(kg: Double, reps: Int) throws {
        guard draft?.phase == .prepared else { throw GymaError.stale("Finish reviewing the current set first.") }
        try validateValues(kg: kg, reps: reps)
        draft?.kg = kg; draft?.expectedReps = reps
        draft?.actualKg = kg; draft?.actualReps = reps
    }

    public mutating func start(snapshot: CompanionSnapshot) throws {
        guard draft?.phase == .prepared, draft?.matches(snapshot) == true, snapshot.restTimer == nil else {
            throw GymaError.stale("Review the current exercise before starting this set.")
        }
        draft?.phase = .performing
    }

    public mutating func done(snapshot: CompanionSnapshot) throws {
        guard draft?.phase == .performing, draft?.matches(snapshot) == true, snapshot.restTimer == nil else {
            throw GymaError.stale("The workout changed. Your set details are still saved on this Watch.")
        }
        draft?.phase = .review; draft?.reviewStep = .reps
    }

    public mutating func setActual(kg: Double, reps: Int) throws {
        guard draft?.phase == .review else { throw GymaError.stale("Complete the set before confirming your reps.") }
        try validateValues(kg: kg, reps: reps)
        if draft?.currentReviewStep == .weight, reps != draft?.actualReps { draft?.reviewStep = .reps }
        draft?.actualKg = kg; draft?.actualReps = reps
    }

    public mutating func confirmReps() throws {
        guard let current = draft, current.phase == .review, current.currentReviewStep == .reps else {
            throw GymaError.stale("Review your completed reps before confirming them.")
        }
        try validateValues(kg: current.actualKg, reps: current.actualReps)
        draft?.reviewStep = .weight
    }

    public mutating func backToReps() throws {
        guard draft?.phase == .review, draft?.currentReviewStep == .weight else {
            throw GymaError.stale("Finish the current review step first.")
        }
        draft?.reviewStep = .reps
    }

    /// Capture the CURRENT revision only after checking the original set position.
    /// Persist the result before submitting; retries keep one completed-set ID.
    public mutating func prepareSubmission(snapshot: CompanionSnapshot) throws -> WorkSet {
        guard let current = draft, current.phase == .review, current.matches(snapshot), snapshot.restTimer == nil else {
            throw GymaError.stale("The workout advanced. Review your saved set before continuing.")
        }
        guard current.currentReviewStep == .weight else { throw GymaError.invalid("Confirm your reps before confirming the weight.") }
        try validateValues(kg: current.actualKg, reps: current.actualReps)
        let set = WorkSet(id: current.setID ?? UUID().uuidString, kg: current.actualKg,
                          reps: current.actualReps, isWarmup: false)
        draft?.setID = set.id; draft?.completionRevision = snapshot.revision; draft?.phase = .submitting
        return set
    }

    public mutating func markSubmitted(_ command: WatchCommand) {
        guard case let .logSet(_, set) = command.action, set.id == draft?.setID else { return }
        draft?.commandID = command.id
    }

    public mutating func submissionFailed() {
        if draft?.phase == .submitting { draft?.reviewStep = .weight }
        draft?.phase = .review; draft?.commandID = nil; draft?.completionRevision = nil
    }

    public mutating func prepareRestResume(snapshot: CompanionSnapshot) throws {
        guard let timer = snapshot.restTimer, let draft, draft.matches(snapshot),
              draft.phase == .prepared, timer.workoutID == draft.workoutID else {
            throw GymaError.stale("The rest or workout changed. Review your next set.")
        }
        resumeRestTimer = timer
    }

    public mutating func markRestSubmitted(_ command: WatchCommand) {
        guard case let .skipRest(timerID) = command.action, resumeRestTimer?.id == timerID else { return }
        resumeCommandID = command.id
    }

    public mutating func restSubmissionFailed() { resumeRestTimer = nil; resumeCommandID = nil }

    /// Only invoke after an explicit user action when an unsent draft no longer
    /// matches the phone's session. Reconciliation never discards that draft.
    public mutating func useCurrentWorkout(_ snapshot: CompanionSnapshot) {
        draft = nil; resumeRestTimer = nil; resumeCommandID = nil
        advance(snapshot)
    }

    private mutating func advance(_ snapshot: CompanionSnapshot) {
        guard let workout = snapshot.activeWorkout, let next = workout.nextExercise else {
            draft = nil
            return
        }
        let previous = draft
        let sameExercise = previous?.storeID == snapshot.storeID && previous?.workoutID == workout.id &&
            previous?.exerciseID == next.exerciseID
        draft = WatchSetDraft(snapshot: snapshot, workout: workout, exercise: next,
                              kg: sameExercise ? previous?.actualKg : nil,
                              expectedReps: sameExercise ? previous?.expectedReps : nil)
    }

    private func containsSubmittedSet(_ snapshot: CompanionSnapshot, draft: WatchSetDraft) -> Bool {
        guard snapshot.storeID == draft.storeID, snapshot.activeWorkout?.id == draft.workoutID,
              let setID = draft.setID else { return false }
        return snapshot.activeWorkout?.exercises.first { $0.exerciseID == draft.exerciseID }?
            .sets.contains { $0.id == setID } == true
    }

    private func validateValues(kg: Double, reps: Int) throws {
        guard kg.isFinite, (0...1000).contains(kg), (1...100).contains(reps) else {
            throw GymaError.invalid("Choose a load from 0–1000 kg and 1–100 reps.")
        }
    }
}

private extension CommandAcknowledgement {
    var wasApplied: Bool { status == .applied || (status == .duplicate && originalStatus == .applied) }
}
