import Foundation
import GymaCore

/// Shared wording for the same calendar eligibility used when a workout actually starts.
struct DailyTrainingPresentation {
    let state: GymaState
    let now: Date

    var status: DailyTrainingStatus { state.dailyTrainingStatus(now: now) }

    func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = state.planningCalendar()
        formatter.timeZone = formatter.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: value)
    }

    var nextTrainingDate: Date? {
        guard let plan = state.trainingCalendar else { return nil }
        let today = plan.calendar.startOfDay(for: now)
        return plan.entries(program: state.trainingProgram, history: state.workouts, now: now)
            .first { $0.date >= today && $0.isTraining && $0.workouts.isEmpty }?.date
    }

    var title: String {
        switch status {
        case .beforeStart(let start): return "Your block starts\n\(date(start))."
        case .recoveryDay: return "Recovery day."
        case .completedToday: return "Today's training\nis complete."
        case .blockComplete: return "Your eight weeks\nare complete."
        case .activeWorkout: return "Pick up where\nyou left off."
        case .unavailable: return "Review your\ntraining calendar."
        case .noCalendar, .trainingDay: return "Today's training."
        }
    }

    var message: String {
        switch status {
        case .beforeStart:
            return "Today is \(date(now)). No strength workout is scheduled for today. You can review your program and upcoming dates."
        case .recoveryDay:
            return "No strength workout is scheduled for today. \(activitySummary)"
        case .completedToday:
            return "Your workout is saved in History and Progress. \(activitySummary)"
        case .blockComplete:
            return "Review your progress and set up your next calendar block. Your previous workouts and weights stay in History and Progress."
        case .activeWorkout:
            return "Resume your current workout whenever you are ready."
        case .unavailable:
            return "Your saved calendar needs attention before a workout can start."
        case .trainingDay:
            return "Strength training is scheduled for today. Check your energy, sleep and soreness before starting."
        case .noCalendar:
            return "Check your energy, sleep and soreness before starting this session."
        }
    }

    var sessionPreviewDate: String {
        if let nextTrainingDate { return "Scheduled for \(date(nextTrainingDate))" }
        return state.trainingCalendar == nil ? "Next in your program" : "No remaining training date in this block"
    }

    private var activitySummary: String {
        let activities = state.trainingCalendar?.activities(on: now) ?? []
        guard !activities.isEmpty else { return "Rest, or add an optional activity in your calendar if you feel recovered." }
        return "Today's optional activities: " + activities.map {
            "\($0.kind.title) · \($0.durationMinutes) min\($0.isCompleted ? " (done)" : "")"
        }.joined(separator: "; ") + "."
    }
}
