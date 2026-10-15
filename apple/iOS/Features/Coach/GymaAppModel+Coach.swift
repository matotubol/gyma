import Foundation
import GymaCore

extension GymaAppModel {
    var hasCoachAPIKey: Bool { coachSession.hasAPIKey }
    var coachRequestInFlight: Bool { coachSession.requestInFlight }
    var coachError: String? { coachSession.error }
    var coachAppChanges: CoachAppChangeProposal? { coachSession.appChanges }

    /// General app management is available without a readiness check or a new program request.
    @discardableResult
    func beginCoachDiscussion(replacingConversation: Bool = false) -> Bool {
        guard !storageBlocked else { return false }
        if !replacingConversation, state.coachConversation?.startedWorkoutID == nil,
           state.coachConversation != nil { return true }
        cancelCoachRequest()
        var conversation = CoachConversation.programPlanning(profile: state.athleteProfile, existingProgram: state.trainingProgram)
        conversation.messages = []
        guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
        coachSession.appChanges = nil
        coachSession.error = nil
        return true
    }

    @discardableResult
    func sendCoachMessage(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !coachSession.requestInFlight,
              var conversation = state.coachConversation, conversation.startedWorkoutID == nil else { return false }
        guard text.count <= 16_000 else {
            coachSession.error = "Keep your message under 16,000 characters."
            return false
        }
        // A failed request leaves its user message saved. Sending the same text retries it.
        if conversation.messages.last?.role != .user || conversation.messages.last?.content != text {
            conversation.messages.append(CoachMessage(role: .user, content: text))
        }
        conversation.acceptedProgramID = nil
        conversation.proposedExercises = nil
        guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
        requestCoachReply()
        return true
    }

    func requestCoachReply() {
        guard !coachSession.requestInFlight, !storageBlocked,
              let conversation = state.coachConversation, conversation.startedWorkoutID == nil,
              conversation.messages.last?.role == .user else { return }
        let apiKey: String
        do {
            guard let saved = try CoachCredentials.load(), !saved.isEmpty else {
                coachSession.hasAPIKey = false
                coachSession.error = "Add your OpenAI API key in Settings to talk with your coach."
                return
            }
            apiKey = saved
            coachSession.hasAPIKey = true
        } catch {
            coachSession.error = "Your OpenAI key could not be read. \(error.localizedDescription)"
            return
        }
        coachSession.error = nil
        coachSession.requestInFlight = true
        let generation = UUID()
        coachGeneration = generation
        let requestState = state
        let pendingAppChanges = coachSession.appChanges
        coachTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if coachGeneration == generation {
                    coachSession.requestInFlight = false
                    coachTask = nil
                }
            }
            do {
                let reply = try await OpenAICoachService.reply(conversation: conversation, state: requestState, apiKey: apiKey,
                                                            pendingAppChanges: pendingAppChanges)
                // A restore, replacement discussion, or edited conversation must never receive an old reply.
                guard !Task.isCancelled, coachGeneration == generation,
                      state.coachConversation == conversation,
                      state.storeID == requestState.storeID, state.revision == requestState.revision else {
                    if !Task.isCancelled { coachSession.error = "Your profile, program or training changed while the coach replied. Try again with the latest information." }
                    return
                }
                var next = conversation
                next.messages.append(CoachMessage(role: .assistant, content: reply.message))
                // A question about data must not revoke a workout that is already ready.
                if let plan = reply.plan {
                    next.plan = plan
                    next.plan?.acceptedAt = nil
                } else if reply.program != nil || !reply.proposedExercises.isEmpty || conversation.plan?.acceptedAt == nil {
                    next.plan = nil
                }
                next.proposedProgram = reply.program
                next.proposedExercises = reply.proposedExercises.isEmpty ? nil : reply.proposedExercises
                next.acceptedProgramID = nil
                // Rebase only the conversation save, never a concurrent training edit.
                // Stage against exactly the state that will be persisted with this reply.
                var savedState = state
                try savedState.saveCoachConversation(next)
                let proposal = try reply.appChanges.map {
                    try CoachAppChangeProposal(changes: $0.changes, state: savedState)
                }
                if update({ $0 = savedState }) {
                    coachSession.appChanges = proposal
                } else {
                    coachSession.error = "The reply could not be saved. Your conversation and previous draft are still available. Try again."
                }
            } catch {
                guard !Task.isCancelled, coachGeneration == generation else { return }
                coachSession.error = error.localizedDescription
            }
        }
    }

    func cancelCoachRequest() {
        coachGeneration = UUID()
        coachTask?.cancel()
        coachTask = nil
        coachSession.requestInFlight = false
    }

    var canApplyCoachAppChanges: Bool {
        guard let proposal = coachSession.appChanges else { return false }
        return !storageBlocked && !coachSession.requestInFlight
            && proposal.baseStoreID == state.storeID && proposal.baseRevision == state.revision
    }

    @discardableResult
    func applyCoachAppChanges(_ proposal: CoachAppChangeProposal) -> Bool {
        guard canApplyCoachAppChanges, coachSession.appChanges == proposal else { return false }
        let applied = update { state in
            try state.applyCoachAppChanges(proposal)
            if var conversation = state.coachConversation {
                conversation.messages.append(.init(role: .assistant,
                    content: "App confirmation — changes saved:\n" + String(proposal.summaries.joined(separator: "\n").prefix(12_000))))
                try state.saveCoachConversation(conversation)
            }
        }
        if applied { coachSession.appChanges = nil; coachSession.error = nil }
        return applied
    }

    func discardCoachAppChanges() {
        guard let proposal = coachSession.appChanges, !coachSession.requestInFlight else { return }
        if update({ state in
            if var conversation = state.coachConversation {
                conversation.messages.append(.init(role: .assistant,
                    content: "App confirmation — the proposed changes were dismissed without being applied:\n" + String(proposal.summaries.joined(separator: "\n").prefix(12_000))))
                try state.saveCoachConversation(conversation)
            }
        }) { coachSession.appChanges = nil }
    }

    var canAcceptCoachPlan: Bool {
        !storageBlocked && !coachSession.requestInFlight && state.activeWorkout == nil
            && state.coachConversation?.startedWorkoutID == nil
            && state.coachConversation?.messages.last?.role == .assistant
            && state.coachConversation?.plan != nil
    }

    @discardableResult
    func acceptCoachPlan(_ planID: String) -> Bool {
        guard canAcceptCoachPlan else { return false }
        return update { try $0.acceptCoachPlan(planID: planID) }
    }

    @discardableResult
    func acceptCoachProgram(_ programID: String) -> Bool {
        guard !storageBlocked, !coachSession.requestInFlight, state.activeWorkout == nil,
              state.coachConversation?.messages.last?.role == .assistant else { return false }
        return update { try $0.acceptProgramProposal(programID: programID) }
    }

    @discardableResult
    func acceptCoachExercises(_ proposals: [CoachExerciseProposal]) -> Bool {
        guard !storageBlocked, !coachSession.requestInFlight, state.activeWorkout == nil,
              !proposals.isEmpty, state.coachConversation?.messages.last?.role == .assistant else { return false }
        guard update({ try $0.acceptCoachExerciseProposals(proposals) }) else { return false }
        coachSession.error = nil
        requestCoachReply()
        return true
    }
}
