import Foundation

// Port of gym-web/web/src/records.ts: personal records, kg suggestions and celebration copy.

public enum RecordKind: String, Sendable { case weight, reps, e1rm, volume }

public struct SetRecord: Sendable, Equatable {
    public let kinds: [RecordKind]
    public let kg: Double
    public let reps: Int
    public let previousKg: Double
    public let previousReps: Int
    public let e1rm: Double
    public let gain: Double
    public let volume: Double
}

public struct Baseline: Sendable, Equatable {
    public var bestKg: Double
    public var bestE1rm: Double
    public var bestVolume: Double
    public var repsByKg: [LiftedSet]
    public var sessionVolume: Double
}

public struct Celebration: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let monster: Bool
}

public struct WorkoutAnalysis: Sendable {
    /// Record-setting sets keyed by set ID.
    public let records: [String: SetRecord]
    /// History plus everything lifted so far today, keyed by library exercise ID.
    public let baselines: [String: Baseline]
}

/// Estimated one-rep max (Epley). A single rep is the max itself.
public func e1rm(_ kg: Double, _ reps: Int) -> Double {
    reps <= 0 ? 0 : reps == 1 ? kg : kg * (1 + Double(reps) / 30)
}

/// Plate/stack increment for the − / + steppers.
public func kgStep(_ equipment: Equipment) -> Double {
    switch equipment {
    case .machine: 5
    case .dumbbell: 2
    default: 2.5
    }
}

/// "82.5", "80", "0.25": at most two decimals, no trailing zeros.
public func formatKg(_ kg: Double) -> String {
    var text = String(format: "%.2f", roundKg(kg))
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text == "-0" ? "0" : text
}

public func formatSet(_ set: LiftedSet) -> String { "\(formatKg(set.kg)) × \(set.reps)" }

private func repsAtOrAbove(_ baseline: Baseline, _ kg: Double) -> Int {
    baseline.repsByKg.filter { $0.kg >= kg }.map(\.reps).reduce(0, max)
}

private func baselineFrom(_ history: ExerciseHistory) -> Baseline {
    let lifted = history.bestRepsByKg.filter { $0.reps > 0 }
    return Baseline(
        bestKg: lifted.map(\.kg).reduce(0, max),
        bestE1rm: lifted.map { e1rm($0.kg, $0.reps) }.reduce(0, max),
        bestVolume: history.bestVolume, repsByKg: history.bestRepsByKg, sessionVolume: 0)
}

private func absorb(_ baseline: inout Baseline, _ kg: Double, _ reps: Int) {
    if reps > 0 {
        baseline.bestKg = max(baseline.bestKg, kg)
        baseline.bestE1rm = max(baseline.bestE1rm, e1rm(kg, reps))
    }
    if let index = baseline.repsByKg.firstIndex(where: { $0.kg == kg }) {
        baseline.repsByKg[index].reps = max(baseline.repsByKg[index].reps, reps)
    } else {
        baseline.repsByKg.append(LiftedSet(kg: kg, reps: reps))
    }
}

private func chronological(_ a: PerformedSet, _ b: PerformedSet) -> Bool {
    let left = a.completedAt ?? "", right = b.completedAt ?? ""
    if left != right { return left < right }
    if a.exercisePosition != b.exercisePosition { return a.exercisePosition < b.exercisePosition }
    return a.setNumber < b.setNumber
}

/// Replays this workout's completed sets, in the order they were done, against everything lifted on
/// earlier dates. A set is a record only when it strictly beats the history plus the sets before it,
/// so one great set is celebrated once. An exercise with no history only sets the baseline.
public func analyseWorkout(_ session: WorkoutSession) -> WorkoutAnalysis {
    var records: [String: SetRecord] = [:]
    var baselines: [String: Baseline] = [:]
    for history in session.history { baselines[history.exerciseId] = baselineFrom(history) }
    var exerciseAt: [Int: String] = [:]
    for exercise in session.exercises { exerciseAt[exercise.position] = exercise.exerciseId }

    for set in session.sets.filter({ $0.status == .completed }).sorted(by: chronological) {
        guard let exerciseId = exerciseAt[set.exercisePosition], var baseline = baselines[exerciseId] else { continue }
        let kg = set.actualKg ?? 0, reps = set.actualReps ?? 0
        let previousReps = repsAtOrAbove(baseline, kg)
        let estimate = e1rm(kg, reps)
        var kinds: [RecordKind] = []
        if reps > 0 && kg > baseline.bestKg { kinds.append(.weight) }
        if reps > previousReps && baseline.repsByKg.contains(where: { $0.kg >= kg }) { kinds.append(.reps) }
        if reps > 0 && estimate > baseline.bestE1rm + 0.005 { kinds.append(.e1rm) }
        let volume = roundKg(baseline.sessionVolume + kg * Double(reps))
        if baseline.bestVolume > 0 && baseline.sessionVolume <= baseline.bestVolume && volume > baseline.bestVolume { kinds.append(.volume) }
        if !kinds.isEmpty {
            records[set.id] = SetRecord(
                kinds: kinds, kg: kg, reps: reps, previousKg: baseline.bestKg, previousReps: previousReps, e1rm: estimate,
                gain: baseline.bestE1rm > 0 ? estimate / baseline.bestE1rm - 1 : 0, volume: volume)
        }
        baseline.sessionVolume = volume
        absorb(&baseline, kg, reps)
        baselines[exerciseId] = baseline
    }
    return WorkoutAnalysis(records: records, baselines: baselines)
}

public enum RecordTarget: Sendable, Equatable {
    /// Any completed rep at this weight is a record.
    case any
    case reps(Int)
}

/// The fewest reps at this weight that would set a record, or nil when out of reach / no history.
public func repsForRecord(_ baseline: Baseline?, kg: Double) -> RecordTarget? {
    guard let baseline, kg.isFinite, kg >= 0 else { return nil }
    if kg > baseline.bestKg && kg > 0 { return .any }
    var reps = baseline.repsByKg.contains(where: { $0.kg >= kg }) ? repsAtOrAbove(baseline, kg) + 1 : Int.max
    // Only targets up to 50 reps are shown, so the search stops there.
    for candidate in stride(from: 1, to: min(reps, 51), by: 1) where e1rm(kg, candidate) > baseline.bestE1rm + 0.005 {
        reps = candidate
        break
    }
    return reps <= 50 ? .reps(reps) : nil
}

public struct KgPlan: Sendable, Equatable {
    public enum Recommendation: Sendable { case repeatWeight, push }
    public let repeatKg: Double
    public let pushKg: Double
    public let recommend: Recommendation
    public let reason: String
    public let lastKg: Double?
    public let lastReps: [Int]
    public let bestKg: Double?
    public let bestE1rm: Double

    public var recommendedKg: Double { recommend == .push ? pushKg : repeatKg }
}

public struct KgVerdict: Sendable, Equatable {
    public enum Tone: Sendable { case pr, up, same, down }
    public let tone: Tone
    public let title: String
    public let detail: String
}

/// Double progression: if every top set last time reached the target reps, add one increment;
/// if it fell a little short, repeat the weight; otherwise fall back to the heaviest weight ever done
/// for this many reps, then to an estimate from the best lift.
public func planKg(_ history: ExerciseHistory?, reps: Int, equipment: Equipment) -> KgPlan? {
    guard let history, reps >= 1 else { return nil }
    let lifted = history.bestRepsByKg.filter { $0.reps > 0 }
    guard lifted.contains(where: { $0.kg > 0 }) else { return nil }
    let step = kgStep(equipment)
    let lastLifted = history.lastSets.filter { $0.reps > 0 }
    let lastKg = lastLifted.map(\.kg).max()
    let lastReps = lastLifted.filter { $0.kg == lastKg }.map(\.reps)
    let fewest = lastReps.min() ?? 0
    let bestKg = lifted.filter { $0.reps >= reps }.map(\.kg).max()
    let bestE1rm = lifted.map { e1rm($0.kg, $0.reps) }.max() ?? 0
    let base: Double, recommend: KgPlan.Recommendation, reason: String
    let joined = lastReps.map(String.init).joined(separator: " · ")
    if let lastKg, lastKg != 0, fewest >= reps {
        base = lastKg; recommend = .push
        reason = "You hit \(reps)+ reps on every \(formatKg(lastKg)) kg set last time. Time to add weight."
    } else if let lastKg, lastKg != 0, fewest >= reps - 2 {
        base = lastKg; recommend = .repeatWeight
        reason = "Last time \(joined) reps at \(formatKg(lastKg)) kg. Own all \(reps) first."
    } else if let bestKg, bestKg != 0 {
        base = bestKg; recommend = .repeatWeight
        reason = "Your heaviest for \(reps)+ reps."
    } else {
        let divisor = reps == 1 ? 1 : 1 + Double(reps) / 30
        base = max(step, (bestE1rm / divisor / step).rounded(.down) * step); recommend = .repeatWeight
        reason = "Estimated from your best lift (≈\(Int(bestE1rm.rounded())) kg max)."
    }
    return KgPlan(repeatKg: roundKg(base), pushKg: roundKg(base + step), recommend: recommend, reason: reason,
                  lastKg: lastKg, lastReps: lastReps, bestKg: bestKg, bestE1rm: bestE1rm)
}

/// How a planned load compares with what has been done, phrased to motivate.
public func judgeKg(_ plan: KgPlan, kg: Double, reps: Int) -> KgVerdict? {
    guard kg.isFinite, kg > 0 else { return nil }
    if let best = plan.bestKg, kg > best {
        return KgVerdict(tone: .pr, title: "+\(formatKg(roundKg(kg - best))) kg PR attempt",
                         detail: "Heavier than you've ever done for \(reps) reps (\(formatKg(best)) kg)")
    }
    if plan.bestKg == nil && e1rm(kg, reps) > plan.bestE1rm + 0.005 {
        return KgVerdict(tone: .pr, title: "PR attempt", detail: "\(reps) reps at \(formatKg(kg)) kg beats your best estimated max")
    }
    guard let last = plan.lastKg else { return nil }
    if kg > last { return KgVerdict(tone: .up, title: "+\(formatKg(roundKg(kg - last))) kg vs last time", detail: "Progress. Go get it.") }
    if kg == last {
        return KgVerdict(tone: .same, title: "Same as last time", detail: "Beat \(plan.lastReps.map(String.init).joined(separator: " · ")) reps")
    }
    return KgVerdict(tone: .down, title: "−\(formatKg(roundKg(last - kg))) kg vs last time", detail: "Lighter day. Clean reps.")
}

/// Deterministic choice matching the web client's 32-bit string hash.
func pick(_ options: [String], seed: String) -> String {
    var hash: Int32 = 0
    for unit in seed.utf16 { hash = hash &* 31 &+ Int32(unit) }
    return options[Int(hash.magnitude % UInt32(options.count))]
}

private let groupedNumber: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    return formatter
}()

public func formatNumber(_ value: Double) -> String {
    groupedNumber.string(from: NSNumber(value: value)) ?? formatKg(value)
}

/// Short, varied copy for a record. Big jumps (≥ 5% over the best estimated max) get the loud version.
public func celebrate(_ record: SetRecord, seed: String) -> Celebration {
    let kg = formatKg(record.kg)
    let monster = record.kinds.contains(.e1rm) && record.gain >= 0.05
    let detail: String
    if record.kinds.contains(.weight) { detail = "\(kg) kg × \(record.reps) · was \(formatKg(record.previousKg)) kg" }
    else if record.kinds.contains(.reps) { detail = "\(record.reps) reps at \(kg) kg · was \(record.previousReps)" }
    else if record.kinds.contains(.e1rm) { detail = "Est. max \(Int(record.e1rm.rounded())) kg" }
    else { detail = "\(formatNumber(record.volume)) kg moved today" }
    if monster {
        return Celebration(title: pick(["Okay, monster.", "Absolute unit.", "Who let you cook?", "That’s not normal. Respect.", "Beast mode, confirmed."], seed: seed),
                           detail: detail, monster: true)
    }
    let title: String
    if record.kinds.contains(.weight) { title = pick(["New top weight", "Heaviest ever", "Weight PR"], seed: seed) }
    else if record.kinds.contains(.reps) { title = pick(["+\(record.reps - record.previousReps) reps. Stronger.", "Rep PR", "More reps than ever"], seed: seed) }
    else if record.kinds.contains(.e1rm) { title = pick(["Best lift yet", "Strongest set ever", "New estimated max"], seed: seed) }
    else { title = pick(["Biggest session yet", "Volume record", "Most work ever"], seed: seed) }
    return Celebration(title: title, detail: detail, monster: false)
}
