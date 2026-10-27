import SwiftUI
import GymaCore

/// Owns sign-in, navigation and the selected day's server data. The Worker is the source of
/// truth: every change is an API call, and the returned record replaces the local copy.
@MainActor
final class AppModel: ObservableObject {
    enum Auth { case checking, guest, ready }
    enum Tab: Hashable { case home, workout, progress }
    enum Failure: Error { case conflict, unauthorized, failed }
    enum SaveOutcome { case saved, conflict, failed }

    @Published private(set) var auth: Auth = .checking
    @Published var tab: Tab = .home
    @Published var planEditorOpen = false

    @Published private(set) var selectedDate = CivilDate.today
    @Published private(set) var month = CivilDate.month(of: CivilDate.today)
    @Published private(set) var days: [String: CalendarDay] = [:]
    @Published private(set) var loadedMonth = ""
    @Published private(set) var monthLoading = false
    @Published private(set) var monthError: String?

    @Published private(set) var plan: WorkoutPlan?
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var dayLoading = false
    @Published private(set) var dayError: String?

    /// A plan save or workout change is in flight; controls that change data wait for it.
    @Published private(set) var busy = false
    /// Bumped whenever recorded sets may have changed, so progress charts refresh.
    @Published private(set) var historyRevision = 0

    // Workout presentation shared by the exercise list and the pushed exercise screens.
    @Published var workoutPath: [Int] = []
    @Published var celebration: ShownCelebration?
    @Published var workoutError: String?
    @Published var workoutNeedsReload = false

    private(set) var api: GymAPI?
    private var monthTask: Task<Void, Never>?
    private var dayTask: Task<Void, Never>?

    var isDayReady: Bool { !dayLoading && plan?.date == selectedDate }
    /// The selected day's plan, kept on screen while it refreshes in the background.
    var dayPlan: WorkoutPlan? { plan?.date == selectedDate ? plan : nil }

    // MARK: Sign-in

    func start() async {
        guard auth == .checking else { return }
        guard let token = TokenStore.token else { auth = .guest; return }
        let api = GymAPI(server: TokenStore.server, token: token)
        do {
            try await api.status()
        } catch let error as APIError where error.isUnauthorized {
            TokenStore.clearToken(); auth = .guest; return
        } catch {
            // Offline or the Worker is unreachable: open anyway; each screen reports its own load error.
        }
        self.api = api
        auth = .ready
        reloadAll()
    }

    /// Returns an error message, or nil once signed in.
    func signIn(key: String, server: String) async -> String? {
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" || url.scheme == "http", url.host != nil else { return "Enter a valid server address." }
        let api = GymAPI(server: url, token: token)
        do {
            try await api.status()
            try TokenStore.save(token: token)
            TokenStore.server = url
        } catch let error as APIError where error.isUnauthorized {
            return "That access key didn’t work."
        } catch {
            return "Couldn’t sign in. Please try again."
        }
        self.api = api
        auth = .ready
        reloadAll()
        return nil
    }

    func signOut() {
        TokenStore.clearToken()
        monthTask?.cancel(); dayTask?.cancel()
        api = nil
        days = [:]; loadedMonth = ""; plan = nil; session = nil
        monthError = nil; dayError = nil
        planEditorOpen = false; tab = .home
        workoutPath = []; celebration = nil; workoutError = nil; workoutNeedsReload = false
        auth = .guest
    }

    // MARK: Navigation

    func select(_ date: String) {
        guard !busy else { return }
        let newMonth = CivilDate.month(of: date)
        if newMonth != month { month = newMonth; loadMonth() }
        guard date != selectedDate else { return }
        selectedDate = date
        plan = nil; session = nil
        workoutPath = []; workoutError = nil; workoutNeedsReload = false
        loadDay()
    }

    /// Tapping the selected date again opens its workout.
    func tap(_ date: String) {
        if date == selectedDate { tab = .workout } else { select(date) }
    }

    func open(_ date: String) {
        select(date)
        if selectedDate == date { tab = .workout }
    }

    /// The calendar scrolled to another month.
    func showMonth(_ month: String) {
        guard month != self.month else { return }
        self.month = month
        loadMonth()
    }

    // MARK: Loading

    func reloadAll() { loadMonth(); loadDay() }

    func refresh() async {
        guard auth == .ready, !busy else { return }
        reloadAll()
        await dayTask?.value
    }

    func loadMonth() {
        guard let api else { return }
        monthTask?.cancel()
        let month = month
        monthLoading = true; monthError = nil
        monthTask = Task {
            do {
                let records = try await api.days(month: month)
                guard !Task.isCancelled, month == self.month else { return }
                days = Dictionary(records.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
                loadedMonth = month
            } catch {
                guard !Task.isCancelled else { return }
                if case .unauthorized = classify(error) { return }
                monthError = "Couldn’t load the calendar."
            }
            monthLoading = false
        }
    }

    func loadDay() {
        guard let api else { return }
        dayTask?.cancel()
        let date = selectedDate
        dayLoading = true; dayError = nil; workoutNeedsReload = false
        dayTask = Task {
            do {
                async let plan = api.plan(date: date)
                async let session = api.session(date: date)
                let (loadedPlan, loadedSession) = try await (plan, session)
                guard !Task.isCancelled, date == selectedDate else { return }
                self.plan = loadedPlan
                self.session = loadedSession
            } catch {
                guard !Task.isCancelled, date == selectedDate else { return }
                if case .unauthorized = classify(error) { return }
                dayError = "Couldn’t load this day. Check your connection and try again."
            }
            dayLoading = false
        }
    }

    /// Re-reads performed progress only, keeping the loaded plan.
    func reloadSession() async {
        guard let api, !busy else { return }
        let date = selectedDate
        do {
            let loaded = try await api.session(date: date)
            if date == selectedDate { session = loaded; workoutNeedsReload = false; workoutError = nil }
        } catch {
            if case .unauthorized = classify(error) { return }
            dayError = "Couldn’t load workout progress. Retry before starting a set."
        }
    }

    // MARK: Changes

    func savePlan(date: String, kind: DayKind?, expectedVersion: Int, exercises: [PlannedExerciseInput]) async -> SaveOutcome {
        guard let api, !busy else { return .failed }
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.savePlan(date: date, SaveWorkoutPlan(kind: kind, expectedVersion: expectedVersion, exercises: exercises))
            if saved.date == selectedDate { plan = saved }
            loadMonth()
            return .saved
        } catch {
            switch classify(error) {
            case .conflict: return .conflict
            default: return .failed
            }
        }
    }

    func mutateSession(_ operation: (GymAPI) async throws -> WorkoutSession) async -> Result<WorkoutSession, Failure> {
        guard let api, !busy else { return .failure(.failed) }
        busy = true
        defer { busy = false }
        do {
            let next = try await operation(api)
            if next.date == selectedDate { session = next }
            historyRevision += 1
            return .success(next)
        } catch {
            return .failure(classify(error))
        }
    }

    /// Maps an error, signing out when the key stopped working.
    private func classify(_ error: Error) -> Failure {
        guard let error = error as? APIError else { return .failed }
        if error.isUnauthorized { signOut(); return .unauthorized }
        return error.isConflict ? .conflict : .failed
    }
}
