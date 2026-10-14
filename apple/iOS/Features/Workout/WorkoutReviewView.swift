import SwiftUI
import GymaCore

private enum WorkoutReviewPresentation {
    static func review(for workout: Workout, state: GymaState) -> WorkoutReview {
        if let saved = state.workoutReviews?.first(where: { $0.workoutID == workout.id }) { return saved }
        let program = ([state.trainingProgram].compactMap { $0 } + (state.programHistory ?? []))
            .first { $0.id == workout.programID && $0.revision == workout.programRevision }
        return WorkoutReview.make(workout: workout, history: state.workouts, program: program, catalog: state.catalog,
                                  now: workout.end ?? workout.start)
    }

    static let discussion = "Review this completed workout using my actual sets, recorded effort, program and feedback. Explain what went well, what is uncertain, and what you propose for my next comparable session."
}

struct WorkoutReviewSummarySection: View {
    @EnvironmentObject private var model: GymaAppModel
    let workout: Workout

    var body: some View {
        Section {
            let review = WorkoutReviewPresentation.review(for: workout, state: model.state)
            Text(review.summary).font(.subheadline)
            if let feedback = model.state.workoutFeedback?.first(where: { $0.workoutID == workout.id }),
               !feedback.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Discomfort recorded. Discuss your next target before progressing.", systemImage: "exclamationmark.bubble")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            NavigationLink {
                WorkoutReviewView(workoutID: workout.id)
            } label: {
                Label("Actual results and next targets", systemImage: "chart.bar.doc.horizontal")
            }
            NavigationLink {
                WorkoutCoachView(workoutID: workout.id, initialQuestion: WorkoutReviewPresentation.discussion)
            } label: {
                Label("Discuss workout", systemImage: "bubble.left.and.bubble.right")
            }
        } header: {
            Text("Workout review")
        } footer: {
            Text("Calculated from your saved log. Next targets are proposals for review before another workout.")
        }
        WorkoutFeedbackSection(workoutID: workout.id)
    }
}

struct WorkoutReviewView: View {
    @EnvironmentObject private var model: GymaAppModel
    let workoutID: String

    private var painNeedsReview: Bool {
        let note = model.state.workoutFeedback?.first { $0.workoutID == workoutID }?.painNote ?? ""
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let workout = model.workout(workoutID), !workout.isActive {
                let review = WorkoutReviewPresentation.review(for: workout, state: model.state)
                List {
                    Section {
                        Text(workout.title).font(.headline)
                        Text(review.summary)
                        if painNeedsReview {
                            Label("You recorded discomfort. Review a comfortable next step with the coach before using any progression proposal.", systemImage: "exclamationmark.bubble")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        NavigationLink {
                            WorkoutCoachView(workoutID: workoutID, initialQuestion: WorkoutReviewPresentation.discussion)
                        } label: {
                            Label("Discuss workout", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                    WorkoutFeedbackSection(workoutID: workoutID)
                    ForEach(review.exercises) { entry in
                        Section(entry.exerciseName) {
                            exerciseResult(entry, workout: workout)
                        }
                    }
                    Section {
                        Text("Warm-ups and unclassified sets do not count as working sets. Unknown effort stays unknown. A single session does not establish why performance changed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("Review unavailable", systemImage: "chart.bar.doc.horizontal",
                                       description: Text("Finish a workout to review its recorded results."))
            }
        }
        .navigationTitle("Workout review").navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func exerciseResult(_ entry: ExerciseWorkoutReview, workout: Workout) -> some View {
        if let target = entry.target {
            targetDescription(target, heading: "Planned")
        } else {
            Text("No target was recorded.").font(.subheadline).foregroundStyle(.secondary)
        }
        LabeledContent("Working sets", value: "\(entry.actualWorkingSets)" + (entry.target.map { " / \($0.sets) planned" } ?? ""))
        if let actual = workout.exercises.first(where: { $0.exerciseID == entry.exerciseID }) {
            let working = actual.sets.filter { $0.isWarmup == false }
            if !working.isEmpty {
                Text(working.map { "\($0.kg.gymaNumber) kg × \($0.reps)" }.joined(separator: " · "))
                    .font(.subheadline)
            }
        }
        if let below = entry.setsBelowRepMinimum, below > 0 {
            Text("\(below) working sets below the planned rep range.").font(.caption).foregroundStyle(.secondary)
        }
        if let top = entry.setsAtRepMaximum, top > 0 {
            Text("\(top) working sets reached the top of the rep range.").font(.caption).foregroundStyle(.secondary)
        }
        if entry.warmupSets > 0 { LabeledContent("Warm-up sets", value: "\(entry.warmupSets)").font(.caption) }
        if entry.unclassifiedSets > 0 {
            Text("\(entry.unclassifiedSets) sets were unclassified and excluded from this comparison.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if entry.missingEffortSets > 0 {
            Text("Effort unknown for \(entry.missingEffortSets) working sets.").font(.caption).foregroundStyle(.secondary)
        }
        if let recommendation = entry.recommendation {
            if !painNeedsReview { targetDescription(recommendation.target, heading: "Proposed after this workout") }
            Text(painNeedsReview ? "Discuss the discomfort you recorded before following this target." : recommendation.reason)
                .font(.subheadline).foregroundStyle(painNeedsReview ? Color.orange : Color.secondary)
        } else {
            Text("Discuss the next target with your coach. This workout has no linked program progression proposal.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func targetDescription(_ target: ExerciseTarget, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(target.sets) × \(target.repsMin)–\(target.repsMax) reps · \(target.loadKg.map { "\($0.gymaNumber) kg" } ?? "load to choose")")
                .font(.subheadline.weight(.medium))
            Text("\(target.restSeconds)s rest").font(.caption).foregroundStyle(.secondary)
            if let effort = target.targetEffort {
                Text("Effort target: \(effort.label)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutFeedbackSection: View {
    @EnvironmentObject private var model: GymaAppModel
    let workoutID: String
    @State private var isEditing = false

    private var feedback: WorkoutFeedback? { model.state.workoutFeedback?.first { $0.workoutID == workoutID } }

    var body: some View {
        Section {
            if let feedback, !feedback.note.isEmpty { Text(feedback.note).font(.subheadline) }
            if let feedback, !feedback.painNote.isEmpty {
                LabeledContent("Pain or discomfort", value: feedback.painNote).font(.subheadline)
            }
            Button(feedback == nil ? "Add workout feedback" : "Edit workout feedback", systemImage: "square.and.pencil") {
                isEditing = true
            }
            .disabled(model.storageBlocked)
        } header: {
            Text("Your feedback")
        } footer: {
            Text("Optional: explain skipped work, time limits or discomfort so your coach can interpret the log.")
        }
        .sheet(isPresented: $isEditing) {
            WorkoutFeedbackEditor(workoutID: workoutID, feedback: feedback)
        }
    }
}

private struct WorkoutFeedbackEditor: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var note: String
    @State private var painNote: String
    @State private var error: String?

    init(workoutID: String, feedback: WorkoutFeedback?) {
        self.workoutID = workoutID
        _note = State(initialValue: feedback?.note ?? "")
        _painNote = State(initialValue: feedback?.painNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("How did it go?") {
                    TextField("What worked, skipped exercises, time or equipment limits…", text: $note, axis: .vertical)
                        .lineLimit(4...8)
                    Text("\(note.count) / 2,000 characters").font(.caption).foregroundStyle(.secondary)
                }
                Section("Pain or discomfort") {
                    TextField("Where and when, if any…", text: $painNote, axis: .vertical)
                        .lineLimit(3...6)
                    Text("Separate from normal muscle soreness. Leave blank if there is nothing to report.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Workout feedback").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let feedback = WorkoutFeedback(workoutID: workoutID,
                                                       note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       painNote: painNote.trimmingCharacters(in: .whitespacesAndNewlines))
                        if model.update({ try $0.saveWorkoutFeedback(feedback) }) { dismiss() }
                        else { error = model.errorMessage }
                    }
                    .disabled(model.storageBlocked || note.count > 2000 || painNote.count > 2000)
                }
            }
        }
    }
}
