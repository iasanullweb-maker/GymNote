import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    @ObservationIgnored private var replacingData = false
    @ObservationIgnored private var previewOnly = false
    @ObservationIgnored lazy var account = AccountModel(model: self)
    private(set) var selection = StoreSelection(userID: nil)
    var storageError: String?
    var data: AppData = .empty {
        didSet {
            if !previewOnly, oldValue.dailyItems != data.dailyItems || oldValue.dailyCompletions != data.dailyCompletions
                || oldValue.dailyReminders != data.dailyReminders {
                refreshReminders()
            }
            guard !previewOnly, !replacingData, oldValue != data else { return }
            do {
                let saved = try SharedStore.persistEdits(from: oldValue, to: data, selection: selection)
                if saved != data { replaceData(saved) }
                account.scheduleSync()
                if oldValue.activeWorkout != data.activeWorkout { refreshWorkoutActivity() }
            } catch {
                replaceData(oldValue)
                storageError = "기록을 저장하지 못했어요. 원본 파일은 유지됩니다. 기기를 잠금 해제하고 다시 시도해 주세요."
            }
        }
    }
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    var restStart: Date?
    var restEnd: Date?
    @ObservationIgnored private var activityTask: Task<Void, Never>?

    private func refreshWorkoutActivity(notify: Bool = false) {
        guard !previewOnly else { return }
        activityTask?.cancel()
        let startedAt = data.activeWorkout?.startedAt
        let start = restStart
        let end = restEnd
        let next = data.nextUp(on: workoutDate)
        let owner = selection.generation.uuidString
        let sound = data.restSound
        let shouldNotify = notify || (start != nil && end.map { $0 > Date() } == true)
        activityTask = Task {
            await RestController.update(workoutStartedAt: startedAt, restStart: start, restEnd: end,
                                        title: next.title, info: next.info, generation: owner, notify: shouldNotify, sound: sound)
        }
    }

    var todayPlan: DayPlan { data.activeWorkout?.plan ?? data.plan() }
    var workoutDate: Date { data.activeWorkout?.startedAt ?? Date() }
    var workoutProgress: (done: Int, total: Int) {
        if let session = data.activeWorkout { return (session.done, session.total) }
        return data.progress()
    }
    var savedToday: Bool { data.hasSavedWorkout() }

    func startWorkout() { data.startWorkout() }

    /// 운동을 마쳐 새 최고기록이 생기면 보여 줄 문구 (운동 화면의 알림)
    var recordMessage: String?

    func finishWorkout() {
        let before = data.exerciseRecords()
        if data.activeWorkout?.done == 0 { data.activeWorkout = nil }
        else { data.finishWorkout() }
        stopRest()
        announceRecords(since: before)
    }

    /// 운동 일지에서 다시 계산한 최고기록이 이전보다 좋아졌으면 알림 문구를 남긴다.
    private func announceRecords(since before: [String: ExerciseRecords]) {
        let messages = data.recordImprovements(since: before)
        if !messages.isEmpty { recordMessage = messages.joined(separator: "\n") }
    }

    // 미리보기에서는 실제 계정 저장소를 열거나 샘플 데이터로 덮어쓰지 않음.
    init(previewData: AppData) {
        previewOnly = true
        replaceData(previewData)
    }

    init() {
        do {
            selection = try SharedStore.activate(userID: nil)
            // 저장된 기록을 불러오는 것은 '수정'이 아니다. 일반 대입은 didSet의 저장 병합을 실행해
            // 빈 데이터 → 불러온 데이터 차이를 한 번 더 적용하므로(진행 중 세트 수가 늘어남) 교체 경로로 읽는다.
            replaceData(try SharedStore.snapshot(userID: nil).data)
        } catch { storageError = "기록을 읽지 못했어요. 원본을 덮어쓰지 않고 보관합니다." }
    }

    /// 일상 알림을 현재 계정·데이터 기준으로 다시 예약한다. 연속 변경은 잠깐 모아서 한 번에 처리.
    func refreshReminders() {
        guard !previewOnly else { return }
        reminderTask?.cancel()
        reminderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            DailyReminderScheduler.refresh(data: self.data, generation: self.selection.generation.uuidString)
        }
    }

    func replaceData(_ value: AppData) {
        replacingData = true
        data = value
        replacingData = false
        refreshWorkoutActivity()
    }

    func switchAccount(_ userID: UUID?) async throws {
        activityTask?.cancel()
        await RestController.stop()
        restStart = nil
        restEnd = nil
        let next = try SharedStore.activate(userID: userID)
        selection = next
        replaceData(.empty)
        do { replaceData(try SharedStore.snapshot(userID: userID).data) }
        catch {
            storageError = "기록을 읽지 못했어요. 원본을 덮어쓰지 않고 보관합니다."
            throw error
        }
        storageError = nil
        refreshReminders() // 이전 계정의 알림 정리
    }

    func reload() {
        do { replaceData(try SharedStore.snapshot(userID: selection.userID).data) }
        catch { storageError = "기록을 읽지 못했어요. 기기를 잠금 해제하고 다시 시도해 주세요." }
        // 날짜가 바뀌어도 진행 중 운동은 사용자가 마칠 때까지 이어서 복원한다.
        if let rest = RestController.current(), rest.end > Date() {
            restStart = rest.start
            restEnd = rest.end
        } else {
            restStart = nil
            restEnd = nil
        }
        refreshWorkoutActivity()
        refreshReminders() // 날짜가 바뀌었거나 위젯·알림 버튼으로 바뀐 기록 반영
    }

    /// 세트 완료 → 기록하고 설정한 기본 휴식(모든 운동 공통) 타이머 시작.
    /// 마지막 세트까지 끝나 운동이 일지로 저장되면 휴식은 켜지 않는다.
    func completeSet(_ exercise: Exercise, actualReps: Int? = nil) {
        guard data.activeWorkout != nil else { return }
        let date = workoutDate
        let before = data.exerciseRecords()
        data.changeSets(exercise.id, by: 1, on: date, actualReps: actualReps)
        // 마지막 세트로 운동이 자동 종료되면 일지가 저장되므로 최고기록도 바로 갱신된다.
        if data.activeWorkout == nil { stopRest(); announceRecords(since: before); return }
        let progress = workoutProgress
        guard progress.done < progress.total else { return }
        startDefaultRest()
    }

    func undoSet(_ exercise: Exercise) {
        data.changeSets(exercise.id, by: -1, on: workoutDate)
    }

    func startRest(seconds: Int, title: String, info: String) {
        let now = Date()
        restStart = now
        restEnd = now.addingTimeInterval(TimeInterval(max(seconds, 5)))
        refreshWorkoutActivity(notify: true)
    }

    func startDefaultRest() {
        let next = data.nextUp(on: workoutDate)
        startRest(seconds: data.defaultRest, title: next.title, info: next.info)
    }

    func adjustDefaultRest(by delta: Int) {
        let range = SettingsView.restRange
        data.defaultRest = min(max(data.defaultRest + delta, range.lowerBound), range.upperBound)
    }

    func stopRest() {
        restStart = nil
        restEnd = nil
        refreshWorkoutActivity()
    }

    @discardableResult
    func addRecord(_ entry: RecordEntry) -> Bool {
        guard let definition = account.catalogTypes.first(where: { $0.id == entry.typeID && $0.active }),
              entry.value.isFinite, entry.value >= 0, entry.value <= 1_000_000,
              entry.extraReps >= 0, entry.extraReps <= 1_000_000 else {
            storageError = "입력할 수 없는 종목 또는 기록이에요. 공통 목록과 입력값을 확인해 주세요."
            return false
        }
        var next = data
        if !next.recordTypes.contains(where: { $0.id == definition.id }) {
            next.recordTypes.append(definition.recordType)
        }
        let previous = next.best(definition.recordType)
        next.records.append(entry)
        data = next
        guard data.records.contains(where: { $0.id == entry.id }) else { return false }
        return previous.map { definition.recordType.isBetter(entry, than: $0) } ?? true
    }
}
