import XCTest
@testable import GymNote

final class WorkoutInsightsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)

    private func session(name: String = "푸쉬업", reps: [Int?] = [10, 8], daysAgo: Int = 1) -> WorkoutSession {
        let exercise = Exercise(name: name, sets: reps.count, detail: "10회")
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: date)!
        var session = WorkoutSession(startedAt: start, endedAt: start.addingTimeInterval(600),
                                     plan: DayPlan(title: "상체", exercises: [exercise]))
        session.completedSets[exercise.id.uuidString] = reps.count
        session.actualReps[exercise.id.uuidString] = reps
        return session
    }

    func testHistoryUsesActualValuesAcrossCopiedIDsAndDoesNotInventMissingCounts() throws {
        var data = AppData(week: [])
        let old = session(reps: [10, nil])
        data.workouts = [old, session(reps: [99, 99], daysAgo: -1)]
        let previous = try XCTUnwrap(data.previousExercise(named: " 푸 쉬 업 ", before: date))
        XCTAssertEqual(previous.session.id, old.id)
        XCTAssertEqual(previous.repetition(at: 0), 10)
        XCTAssertNil(previous.repetition(at: 1))
        XCTAssertNil(previous.repetition(at: 2))
        XCTAssertTrue(previous.text.contains("횟수 미기록"))
        XCTAssertNil(data.previousExercise(named: "푸쉬업", before: date, excluding: old.id))
    }

    func testHistoryDoesNotChooseOneOfDuplicateExerciseNames() {
        var old = session()
        let duplicate = Exercise(name: "푸쉬업", sets: 1, detail: "10회")
        old.plan.exercises.append(duplicate)
        old.completedSets[duplicate.id.uuidString] = 1
        var data = AppData(week: [])
        data.workouts = [old]
        XCTAssertNil(data.previousExercise(named: "푸쉬업", before: date))
    }

    func testSummaryOnlyComparesCompleteMatchingLoadsAndUsesActualReps() {
        var data = AppData(week: [])
        let previous = session(reps: [10, 8])
        var current = session(reps: [12, 10], daysAgo: 0)
        data.workouts = [previous, current]
        XCTAssertEqual(data.workoutSummary(current).repetitionChange, 4)
        XCTAssertEqual(data.workoutSummary(current).duration, 600)
        XCTAssertEqual(data.workoutSummary(current).workoutDays, 2)
        current.actualWeights[current.plan.exercises[0].id.uuidString] = [5, 5]
        XCTAssertNil(data.workoutSummary(current).repetitionChange)
        current.actualWeights = [:]
        current.actualReps[current.plan.exercises[0].id.uuidString] = [12, nil]
        let incompleteValues = data.workoutSummary(current)
        XCTAssertEqual(incompleteValues.recordedReps, 12)
        XCTAssertEqual(incompleteValues.recordedSets, 1)
        XCTAssertNil(incompleteValues.repetitionChange)
        current.actualReps[current.plan.exercises[0].id.uuidString] = [12, 10]
        current.completedSets[current.plan.exercises[0].id.uuidString] = 1
        XCTAssertNil(data.workoutSummary(current).repetitionChange)
    }

    func testManualAndTimeSessionsDoNotInventElapsedTimeOrRepetitions() {
        var old = session(name: "플랭크", reps: [nil])
        old.plan.exercises[0].detail = "1분"
        old.endedAt = nil
        var data = AppData(week: [])
        data.workouts = [old]
        let summary = data.workoutSummary(old)
        XCTAssertNil(summary.duration)
        XCTAssertEqual(summary.recordedSets, 0)
        XCTAssertEqual(summary.recordedReps, 0)
        XCTAssertNil(summary.repetitionChange)
    }

    func testSummaryCountsDaysOnceAndExcludesFutureWorkouts() {
        var data = AppData(week: [])
        let current = session(daysAgo: 0)
        data.workouts = [current, session(daysAgo: 0), session(daysAgo: 6), session(daysAgo: 7), session(daysAgo: -1)]
        XCTAssertEqual(data.workoutSummary(current).workoutDays, 2)
    }

    func testAllStarterConditionsHaveGuidesAndIndependentIDs() throws {
        for equipment in WorkoutEquipment.allCases {
            for experience in WorkoutExperience.allCases {
                for minutes in [15, 30, 45] {
                    let routine = StarterWorkouts.plan(equipment: equipment, experience: experience, minutes: minutes)
                    XCTAssertEqual(routine.exercises.count, minutes == 15 ? 3 : 4)
                    XCTAssertTrue(routine.exercises.allSatisfy { ExerciseGuides.find($0.name)?.equipment == equipment })
                    var data = AppData(week: [])
                    let kept = Exercise(name: "기존", sets: 1, detail: "5회")
                    data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "기존 계획", exercises: [kept])
                    let ids = try XCTUnwrap(data.appendStarterWorkout(routine, on: date))
                    XCTAssertEqual(data.plan(for: date).exercises.first, kept)
                    XCTAssertEqual(data.plan(for: date).title, "기존 계획")
                    XCTAssertTrue(Set(ids).isDisjoint(with: routine.exercises.map(\.id)))
                    XCTAssertTrue(data.workouts.isEmpty)
                    let roundTrip = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
                    XCTAssertEqual(roundTrip.plan(for: date), data.plan(for: date))
                }
            }
        }
    }

    func testStarterDoesNotChangeAnActiveDaysPlan() {
        var data = AppData(week: [])
        data.activeWorkout = session(daysAgo: 0)
        let before = data
        let routine = StarterWorkouts.plan(equipment: .bodyweight, experience: .beginner, minutes: 15)
        XCTAssertNil(data.appendStarterWorkout(routine, on: date))
        XCTAssertEqual(data, before)
    }

    func testReplacementSplitsCompletedSetsAndPreservesActualDataAndJournal() throws {
        var data = AppData(week: [])
        let old = session(reps: [10, nil, nil], daysAgo: 0)
        let exercise = old.plan.exercises[0]
        var active = old
        active.endedAt = nil
        active.completedSets[exercise.id.uuidString] = 1
        active.actualReps[exercise.id.uuidString] = [10]
        active.actualWeights[exercise.id.uuidString] = [5]
        data.activeWorkout = active
        data.logs = [DayLog(day: active.day, doneSets: [exercise.id.uuidString: 1])]
        data.workouts = [session(daysAgo: 2)]
        data.scheduledPlans[active.day] = active.plan
        let before = data
        let replacement = Exercise(name: "벽 푸쉬업", sets: 2, detail: "8회")
        let id = try XCTUnwrap(data.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                            expectedSessionID: active.id, expectedDone: 1))
        let saved = try XCTUnwrap(data.activeWorkout)
        XCTAssertEqual(saved.total, 3)
        XCTAssertEqual(saved.done, 1)
        XCTAssertEqual(saved.plan.exercises[0].id, exercise.id)
        XCTAssertEqual(saved.plan.exercises[0].sets, 1)
        XCTAssertEqual(saved.plan.exercises[1].id, id)
        XCTAssertEqual(saved.plan.exercises[1].sets, 2)
        XCTAssertEqual(saved.actualReps, active.actualReps)
        XCTAssertEqual(saved.actualWeights, active.actualWeights)
        XCTAssertEqual(data.workouts, before.workouts)
        XCTAssertEqual(data.scheduledPlans, before.scheduledPlans)
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.activeWorkout, saved)
        let merged = before.applyingEdits(from: before, to: data)
        var normalized = saved
        // The existing progress merger represents an untouched new exercise with an empty array.
        normalized.actualReps[id.uuidString] = []
        XCTAssertEqual(merged.activeWorkout, normalized)
        data.changeSets(id, by: 1, on: date, actualReps: 8)
        data.changeSets(id, by: 1, on: date, actualReps: 7)
        XCTAssertNil(data.activeWorkout)
        let finished = try XCTUnwrap(data.workouts.first { $0.id == active.id })
        XCTAssertEqual(finished.repetitions(exercise, set: 0), 10)
        XCTAssertEqual(finished.actualWeights[exercise.id.uuidString], [5])
        XCTAssertEqual(finished.actualReps[id.uuidString], [8, 7])
    }

    func testReplacementRejectsStaleSheetAndFinishedExercises() {
        var data = AppData(week: [])
        let active = session(daysAgo: 0)
        data.activeWorkout = active
        let exercise = active.plan.exercises[0]
        let replacement = Exercise(name: "벽 푸쉬업", sets: 2, detail: "8회")
        let before = data
        XCTAssertNil(data.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                   expectedSessionID: UUID(), expectedDone: 0))
        XCTAssertNil(data.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                   expectedSessionID: active.id, expectedDone: 0))
        XCTAssertNil(data.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                   expectedSessionID: active.id, expectedDone: 2))
        XCTAssertEqual(data, before)
    }

    func testReplacementBeforeStartCreatesNewIDsAndPreservesSavedSessions() throws {
        var data = AppData(week: [])
        let exercise = Exercise(name: "푸쉬업", sets: 3, detail: "12회")
        data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "오늘", exercises: [exercise])
        data.workouts = [session()]
        let previous = data.workouts
        let replacement = Exercise(name: "플랭크", sets: 1, detail: "20초")
        let id = try XCTUnwrap(data.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                            expectedSessionID: nil, expectedDone: 0))
        XCTAssertNotEqual(id, exercise.id)
        XCTAssertNotEqual(id, replacement.id)
        XCTAssertEqual(data.plan(for: date).exercises.first?.detail, "20초")
        XCTAssertEqual(data.plan(for: date).totalSets, 3)
        XCTAssertEqual(data.workouts, previous)
    }

    func testAlternativesRespectEquipmentAndDifficultyAndAliases() {
        XCTAssertEqual(ExerciseGuides.find("푸 시 업")?.name, "푸쉬업")
        XCTAssertNil(ExerciseGuides.find("알 수 없는 개인 운동"))
        let easier = ExerciseGuides.alternatives(for: "푸쉬업", equipment: .bodyweight, reason: .difficult)
        XCTAssertEqual(easier.map(\.name), ["벽 푸쉬업"])
        let noEquipment = ExerciseGuides.alternatives(for: "체스트 프레스", equipment: .bodyweight, reason: .unavailable)
        XCTAssertFalse(noEquipment.isEmpty)
        XCTAssertTrue(noEquipment.allSatisfy { $0.equipment == .bodyweight && $0.pattern == "push" })
        XCTAssertTrue(ExerciseGuides.alternatives(for: "플랭크", equipment: nil, reason: .busy).isEmpty)
    }
}

@MainActor
final class WorkoutAssistancePersistenceTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SharedStore.testingDirectory = folder
    }

    override func tearDown() async throws {
        SharedStore.testingDirectory = nil
        try FileManager.default.removeItem(at: folder)
    }

    func testStarterPersistsOnceAndFailedWriteKeepsOriginalPlan() throws {
        let model = AppModel()
        model.data = AppData(week: [])
        let date = model.workoutDate
        let routine = StarterWorkouts.plan(equipment: .bodyweight, experience: .beginner, minutes: 15)
        XCTAssertTrue(model.saveEdit { _ = $0.appendStarterWorkout(routine, on: date) })
        let saved = model.data
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data.plan(for: date), saved.plan(for: date))
        _ = try SharedStore.activate(userID: UUID())
        XCTAssertFalse(model.saveEdit { _ = $0.appendStarterWorkout(routine, on: date) })
        XCTAssertEqual(model.data, saved)
    }

    func testReplacementRejectsWidgetProgressMadeAfterSheetOpened() throws {
        let model = AppModel()
        let exercise = Exercise(name: "푸쉬업", sets: 3, detail: "10회")
        model.data.scheduledPlans[DayKey.key()] = DayPlan(title: "오늘", exercises: [exercise])
        model.startWorkout()
        model.completeSet(exercise, actualReps: 10)
        let base = model.data
        let active = try XCTUnwrap(base.activeWorkout)
        var widget = base
        widget.changeSets(exercise.id, by: 1, on: active.startedAt, actualReps: 11)
        _ = try SharedStore.persistEdits(from: base, to: widget, selection: model.selection)
        var edited = base
        let replacement = Exercise(name: "벽 푸쉬업", sets: 2, detail: "8회")
        XCTAssertNotNil(edited.replaceExecutionExercise(exercise, with: replacement, on: active.startedAt,
                                                        expectedSessionID: active.id, expectedDone: 1))
        XCTAssertTrue(widget.hasStaleWorkoutReplacement(from: base, to: edited))
        XCTAssertFalse(model.saveEdit { $0 = edited })
        let persisted = try SharedStore.snapshot(userID: nil).data
        XCTAssertEqual(persisted.activeWorkout?.actualReps[exercise.id.uuidString], [10, 11])
        XCTAssertEqual(persisted.activeWorkout?.done, 2)
        XCTAssertEqual(persisted.activeWorkout?.plan.exercises.count, 1)
        model.reload()
        XCTAssertEqual(model.data.activeWorkout, persisted.activeWorkout)
    }

    func testReplacementRejectsWidgetStartingWorkoutAfterSheetOpened() throws {
        let model = AppModel()
        let date = Date()
        let exercise = Exercise(name: "푸쉬업", sets: 3, detail: "10회")
        model.data.scheduledPlans[DayKey.key(date)] = DayPlan(title: "오늘", exercises: [exercise])
        let base = model.data
        var widget = base
        XCTAssertTrue(widget.startWorkout(at: date))
        widget.changeSets(exercise.id, by: 1, on: date, actualReps: 10)
        _ = try SharedStore.persistEdits(from: base, to: widget, selection: model.selection)
        let latest = try SharedStore.snapshot(userID: nil).data
        var edited = base
        let replacement = Exercise(name: "벽 푸쉬업", sets: 3, detail: "8회")
        XCTAssertNotNil(edited.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                        expectedSessionID: nil, expectedDone: 0))
        XCTAssertTrue(latest.hasStaleWorkoutReplacement(from: base, to: edited))
        XCTAssertFalse(model.saveEdit { $0 = edited })
        XCTAssertEqual(try SharedStore.snapshot(userID: nil).data, latest,
                       "시작 전 대체가 거부되면 최신 세션과 날짜 계획 모두 보존")
        model.reload()
        XCTAssertEqual(model.data, latest)
    }

    func testReplacementRejectsAnotherDevicesChangedPlanButAllowsIndependentEdits() throws {
        let date = Date()
        let exercise = Exercise(name: "푸쉬업", sets: 3, detail: "10회")
        var base = AppData(week: [])
        base.scheduledPlans[DayKey.key(date)] = DayPlan(title: "오늘", exercises: [exercise])
        var edited = base
        let replacement = Exercise(name: "벽 푸쉬업", sets: 3, detail: "8회")
        XCTAssertNotNil(edited.replaceExecutionExercise(exercise, with: replacement, on: date,
                                                        expectedSessionID: nil, expectedDone: 0))
        XCTAssertFalse(base.hasStaleWorkoutReplacement(from: base, to: edited))
        var changed = base
        changed.scheduledPlans[DayKey.key(date)]?.title = "다른 기기 수정"
        XCTAssertTrue(changed.hasStaleWorkoutReplacement(from: base, to: edited))
        changed = base
        changed.defaultRest += 15
        XCTAssertFalse(changed.hasStaleWorkoutReplacement(from: base, to: edited))
        var appended = base
        _ = appended.appendStarterWorkout(StarterWorkouts.plan(equipment: .bodyweight, experience: .beginner, minutes: 15), on: date)
        XCTAssertFalse(changed.hasStaleWorkoutReplacement(from: base, to: appended))
    }
}
