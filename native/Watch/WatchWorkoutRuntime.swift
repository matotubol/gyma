import Combine
import Foundation
import GymaCore
import HealthKit
import WatchKit

/// Owns the system workout session for the workout already started on iPhone.
/// Gyma keeps its workout record; this session never saves a second Health workout.
@MainActor
final class WatchWorkoutRuntime: NSObject, ObservableObject {
    static let shared = WatchWorkoutRuntime()

    @Published private(set) var isRunning = false
    @Published private(set) var message: String?

    private let healthStore = HKHealthStore()
    private let associationKey = "gyma.watch-workout-runtime.v1"
    private var snapshot: CompanionSnapshot?
    private var didReceiveSnapshot = false
    private var pendingCommand: WatchCommand?
    private var session: HKWorkoutSession?
    private var association: Association?
    private var isAppActive = false
    private var isEnding = false
    private var didRecover = false
    private var recoveryTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var failedIdentity: Identity?
    private var runtimeObserver: ((Bool) -> Void)?
    private var afterStartAttempt: (() async -> Void)?
    private var commandObservation: AnyCancellable?

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: associationKey) {
            association = try? JSONDecoder().decode(Association.self, from: data)
        }
    }

    func observe(connectivity: WorkoutConnectivity, onRunningChange: @escaping (Bool) -> Void,
                 afterStartAttempt: @escaping () async -> Void) {
        runtimeObserver = onRunningChange
        self.afterStartAttempt = afterStartAttempt
        onRunningChange(isRunning)
        // Pending finish must end the system session promptly, including before phone delivery.
        commandObservation = connectivity.$pendingCommand.sink { [weak self] command in
            self?.pendingCommand = command
            self?.reconcile()
        }
    }

    func update(_ snapshot: CompanionSnapshot?, pendingCommand: WatchCommand?) {
        self.snapshot = snapshot
        didReceiveSnapshot = true
        self.pendingCommand = pendingCommand
        recoverIfNeeded()
        reconcile()
    }

    func setAppActive(_ active: Bool) {
        if active && !isAppActive { failedIdentity = nil }
        isAppActive = active
        recoverIfNeeded()
        reconcile()
        if active, isRunning { prepareForegroundAlerts() }
    }

    /// Called by the Watch app delegate when watchOS relaunches an interrupted workout.
    func recoverIfNeeded() {
        guard didReceiveSnapshot, !didRecover, recoveryTask == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            didRecover = true
            if desiredIdentity != nil { message = "Workout mode is unavailable on this Watch. Rest alerts can still appear as notifications." }
            return
        }
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.recoveryTask = nil
                self.didRecover = true
                self.reconcile()
                self.prepareForegroundAlerts()
            }
            do {
                guard let recovered = try await self.healthStore.recoverActiveWorkoutSession() else {
                    self.clearAssociation()
                    return
                }
                self.session = recovered
                recovered.delegate = self
                guard let saved = self.association, saved.identity == self.desiredIdentity,
                      recovered.startDate.map({ abs($0.timeIntervalSince(saved.startedAt)) < 2 }) ?? false,
                      recovered.state == .running || recovered.state == .paused else {
                    self.endSession()
                    return
                }
                self.message = nil
                self.setRunning(true)
            } catch {
                self.clearAssociation()
                // A foreground attempt can still request access and start a fresh session.
                if self.desiredIdentity != nil { self.message = "Could not restore workout mode: \(error.localizedDescription)" }
            }
        }
    }

    private var desiredIdentity: Identity? {
        guard let snapshot, let workout = snapshot.activeWorkout, workout.isActive else { return nil }
        if let pendingCommand, pendingCommand.storeID == snapshot.storeID, pendingCommand.workoutID == workout.id,
           case .finishWorkout = pendingCommand.action { return nil }
        return Identity(storeID: snapshot.storeID, workoutID: workout.id)
    }

    private func reconcile() {
        guard didReceiveSnapshot else { return }
        let desired = desiredIdentity
        if let session {
            if association?.identity != desired || desired == nil { endSession() }
            else if session.state == .ended { sessionEnded(unexpected: !isEnding) }
            return
        }
        guard desired != nil else {
            message = nil
            clearAssociation()
            return
        }
        guard didRecover, recoveryTask == nil, isAppActive, startTask == nil,
              let desired, failedIdentity != desired else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Workout mode is unavailable on this Watch. Rest alerts can still appear as notifications."
            failedIdentity = desired
            return
        }
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.startTask = nil
                self.reconcile()
                self.prepareForegroundAlerts()
            }
            do {
                guard self.desiredIdentity == desired, self.isAppActive else { return }
                let workoutType = HKObjectType.workoutType()
                if self.healthStore.authorizationStatus(for: workoutType) == .notDetermined {
                    // Only foreground UI with an existing phone workout can show this native prompt.
                    try await self.healthStore.requestAuthorization(toShare: [workoutType], read: [])
                }
                guard self.desiredIdentity == desired, self.isAppActive else { return }
                guard self.healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
                    self.failedIdentity = desired
                    self.message = "Allow Gyma workout access in Health settings to keep the workout active and vibrate with your wrist down."
                    return
                }
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .traditionalStrengthTraining
                configuration.locationType = .indoor
                let created = try HKWorkoutSession(healthStore: self.healthStore, configuration: configuration)
                let association = Association(identity: desired, startedAt: Date())
                // Save the store/workout identity before starting, so recovery never adopts a stale session.
                UserDefaults.standard.set(try JSONEncoder().encode(association), forKey: self.associationKey)
                self.association = association
                self.session = created
                self.isEnding = false
                self.message = nil
                created.delegate = self
                // We intentionally do not collect/read Health metrics or call finishWorkout().
                // watchOS may itself generate health samples while a workout session is active.
                created.startActivity(with: association.startedAt)
            } catch {
                self.failedIdentity = desired
                self.message = "Workout mode could not start: \(error.localizedDescription)"
                self.endSession()
            }
        }
    }

    private func endSession() {
        setRunning(false)
        clearAssociation()
        guard let session else { return }
        if session.state == .ended { sessionEnded(unexpected: false); return }
        guard !isEnding else { return }
        isEnding = true
        session.end()
    }

    private func sessionEnded(unexpected: Bool) {
        if unexpected {
            failedIdentity = association?.identity ?? desiredIdentity
            message = "Workout mode stopped. Your Gyma workout is still saved; reopen Gyma to retry background rest alerts."
        }
        // Discard the session's builder rather than creating an empty or duplicate Health workout.
        session?.associatedWorkoutBuilder().discardWorkout()
        session?.delegate = nil
        session = nil
        isEnding = false
        clearAssociation()
        setRunning(false)
        reconcile()
    }

    private func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        runtimeObserver?(running)
    }

    private func clearAssociation() {
        association = nil
        UserDefaults.standard.removeObject(forKey: associationKey)
    }

    private func prepareForegroundAlerts() {
        guard isAppActive, desiredIdentity != nil, startTask == nil, recoveryTask == nil, let afterStartAttempt else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isAppActive, self.desiredIdentity != nil, self.startTask == nil, self.recoveryTask == nil else { return }
            await afterStartAttempt()
        }
    }

    private struct Identity: Codable, Equatable {
        let storeID: String
        let workoutID: String
    }
    private struct Association: Codable {
        let identity: Identity
        let startedAt: Date
    }
}

extension WatchWorkoutRuntime: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            if toState == .ended { self.sessionEnded(unexpected: !self.isEnding) }
            else if !self.isEnding {
                self.setRunning(toState == .running || toState == .paused)
                self.reconcile()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.failedIdentity = self.association?.identity ?? self.desiredIdentity
            self.message = "Workout mode stopped: \(error.localizedDescription)"
            self.endSession()
        }
    }
}

final class GymaWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in WatchWorkoutRuntime.shared.recoverIfNeeded() }
    }
}
