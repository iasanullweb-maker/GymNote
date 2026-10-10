import Foundation

struct ExerciseGuide: Identifiable {
    let name: String
    var aliases: [String] = []
    let equipment: WorkoutEquipment
    let equipmentText: String
    let focus: String
    let pattern: String
    let difficulty: Int
    let cues: [String]
    let mistake: String
    let source: String
    var id: String { AppData.exerciseKey(name) }
    var defaultDetail: String { pattern == "core" ? "20초" : "8회" }
}

enum ReplacementReason: String, CaseIterable, Identifiable {
    case busy = "기구 사용 중"
    case unavailable = "기구 없음"
    case difficult = "너무 어려움"
    var id: String { rawValue }
}

enum ExerciseGuides {
    static let all: [ExerciseGuide] = [
        ExerciseGuide(name: "의자 스쿼트", equipment: .bodyweight, equipmentText: "움직이지 않는 의자",
                      focus: "허벅지·엉덩이", pattern: "squat", difficulty: 0,
                      cues: ["의자를 뒤에 두고 발을 편안한 너비로 벌리세요.", "엉덩이를 뒤로 보내 천천히 앉았다 일어나세요."],
                      mistake: "의자가 밀리거나 앉을 때 몸을 떨어뜨리지 않도록 해요.",
                      source: "https://newsnetwork.mayoclinic.org/discussion/mayo-clinic-minute-fab-5-exercises-to-get-moving/"),
        ExerciseGuide(name: "스쿼트", aliases: ["에어 스쿼트", "맨몸 스쿼트"], equipment: .bodyweight, equipmentText: "맨몸",
                      focus: "허벅지·엉덩이", pattern: "squat", difficulty: 1,
                      cues: ["발바닥을 바닥에 두고 엉덩이와 무릎을 함께 굽히세요.", "편안한 깊이까지 내려간 뒤 천천히 일어나세요."],
                      mistake: "뒤꿈치가 들리거나 무릎이 안쪽으로 모이지 않도록 해요.",
                      source: "https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/squat/vid-20084663"),
        ExerciseGuide(name: "벽 푸쉬업", aliases: ["벽 푸시업"], equipment: .bodyweight, equipmentText: "벽",
                      focus: "가슴·팔 뒤쪽", pattern: "push", difficulty: 0,
                      cues: ["벽에 양손을 대고 몸을 일직선으로 유지하세요.", "팔꿈치를 굽혀 벽에 가까워졌다 천천히 밀어내세요."],
                      mistake: "허리만 꺾어서 벽에 가까워지지 않도록 해요.",
                      source: "https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/strength-training/art-20046031"),
        ExerciseGuide(name: "푸쉬업", aliases: ["푸시업", "팔굽혀펴기"], equipment: .bodyweight, equipmentText: "바닥",
                      focus: "가슴·팔 뒤쪽", pattern: "push", difficulty: 2,
                      cues: ["손으로 바닥을 짚고 머리부터 발까지 몸통을 정렬하세요.", "몸 전체를 함께 낮췄다가 바닥을 밀어 올라오세요."],
                      mistake: "엉덩이가 처지거나 상체만 먼저 올라오지 않도록 해요.",
                      source: "https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/strength-training/art-20046031"),
        ExerciseGuide(name: "글루트 브리지", aliases: ["힙 브리지"], equipment: .bodyweight, equipmentText: "바닥·매트",
                      focus: "엉덩이", pattern: "hip", difficulty: 0,
                      cues: ["누워 무릎을 굽히고 발을 바닥에 놓으세요.", "엉덩이를 들어 몸통과 허벅지를 정렬한 뒤 천천히 내려오세요."],
                      mistake: "높이 들려고 허리를 과하게 젖히지 않도록 해요.",
                      source: "https://www.acefitness.org/resources/everyone/exercise-library/49/glute-bridge/"),
        ExerciseGuide(name: "플랭크", equipment: .bodyweight, equipmentText: "바닥·매트",
                      focus: "몸통", pattern: "core", difficulty: 1,
                      cues: ["팔꿈치를 어깨 아래에 놓고 몸통을 정렬하세요.", "배에 힘을 주고 자연스럽게 호흡하며 자세를 유지하세요."],
                      mistake: "허리가 처지거나 숨을 참지 않도록 해요.",
                      source: "https://www.nasm.org/workout-exercise-guidance"),
        ExerciseGuide(name: "고블릿 스쿼트", equipment: .dumbbell, equipmentText: "덤벨 1개",
                      focus: "허벅지·엉덩이", pattern: "squat", difficulty: 1,
                      cues: ["덤벨을 가슴 앞에서 두 손으로 잡으세요.", "발바닥을 지지하며 앉았다 일어나세요."],
                      mistake: "덤벨을 몸에서 멀리 보내거나 몸통을 무너뜨리지 않도록 해요.",
                      source: "https://www.mayoclinichealthsystem.org/hometown-health/speaking-of-health/pump-you-up-exercise-with-dumbbells-video"),
        ExerciseGuide(name: "덤벨 플로어 프레스", equipment: .dumbbell, equipmentText: "덤벨·바닥·매트",
                      focus: "가슴·팔 뒤쪽", pattern: "push", difficulty: 1,
                      cues: ["바닥에 누워 덤벨을 가슴 양옆에 잡으세요.", "덤벨을 위로 밀고 윗팔이 바닥에 닿을 때까지 천천히 내리세요."],
                      mistake: "팔을 바닥에 부딪치거나 반동으로 밀지 않도록 해요.",
                      source: "https://www.nasm.org/workout-exercise-guidance"),
        ExerciseGuide(name: "덤벨 로우", equipment: .dumbbell, equipmentText: "덤벨",
                      focus: "등", pattern: "row", difficulty: 1,
                      cues: ["엉덩이를 뒤로 보내 몸통을 기울이고 등을 정렬하세요.", "팔꿈치를 뒤로 당긴 뒤 덤벨을 천천히 내리세요."],
                      mistake: "몸통을 비틀거나 반동으로 덤벨을 당기지 않도록 해요.",
                      source: "https://www.mayoclinichealthsystem.org/hometown-health/speaking-of-health/pump-you-up-exercise-with-dumbbells-video"),
        ExerciseGuide(name: "덤벨 루마니안 데드리프트", equipment: .dumbbell, equipmentText: "덤벨",
                      focus: "엉덩이·허벅지 뒤쪽", pattern: "hip", difficulty: 2,
                      cues: ["무릎을 약간 굽히고 덤벨을 몸 가까이에 두세요.", "엉덩이를 뒤로 보내며 낮췄다가 몸통 정렬을 유지하며 일어나세요."],
                      mistake: "허리를 둥글게 말거나 바닥에 닿으려고 무리하게 내리지 않도록 해요.",
                      source: "https://www.acefitness.org/continuing-education/certified/may-2025/8865/the-ace-do-it-better-series-the-romanian-deadlift/"),
        ExerciseGuide(name: "레그 프레스", equipment: .gym, equipmentText: "레그 프레스 머신",
                      focus: "허벅지·엉덩이", pattern: "squat", difficulty: 1,
                      cues: ["좌석에 등을 지지하고 발판에 발을 안정적으로 놓으세요.", "발판을 밀고 몸통 지지를 유지하는 범위까지 천천히 돌아오세요."],
                      mistake: "엉덩이가 좌석에서 들리거나 무릎을 세게 잠그지 않도록 해요.",
                      source: "https://www.nasm.org/resource-center/exercise-library/leg-press"),
        ExerciseGuide(name: "체스트 프레스", aliases: ["체스트 프레스 머신"], equipment: .gym, equipmentText: "체스트 프레스 머신",
                      focus: "가슴·팔 뒤쪽", pattern: "push", difficulty: 1,
                      cues: ["손잡이가 가슴 높이에 오도록 좌석을 조절하세요.", "등을 지지하고 손잡이를 앞으로 밀었다 천천히 돌아오세요."],
                      mistake: "어깨를 귀 쪽으로 끌어올리거나 등을 떼지 않도록 해요.",
                      source: "https://www.nasm.org/resource-center/exercise-library/chest-press-machine"),
        ExerciseGuide(name: "시티드 케이블 로우", aliases: ["케이블 로우"], equipment: .gym, equipmentText: "시티드 케이블 로우 머신",
                      focus: "등", pattern: "row", difficulty: 1,
                      cues: ["발을 지지하고 몸통을 세워 손잡이를 잡으세요.", "팔꿈치를 뒤로 당겼다가 천천히 팔을 펴세요."],
                      mistake: "몸통을 크게 앞뒤로 흔들어 당기지 않도록 해요.",
                      source: "https://www.nasm.org/workout-exercise-guidance"),
        ExerciseGuide(name: "랫 풀다운", aliases: ["렛 풀다운", "랫풀 다운"], equipment: .gym, equipmentText: "랫 풀다운 머신",
                      focus: "등", pattern: "verticalPull", difficulty: 1,
                      cues: ["허벅지 패드를 조절해 몸을 안정적으로 고정하세요.", "바를 몸 앞쪽 가슴 위로 당겼다가 천천히 올리세요."],
                      mistake: "바를 목 뒤로 당기거나 몸통을 크게 젖히지 않도록 해요.",
                      source: "https://www.acefitness.org/resources/everyone/exercise-library/158/seated-lat-pulldown/"),
        ExerciseGuide(name: "풀업", aliases: ["풀 업", "턱걸이"], equipment: .gym, equipmentText: "풀업 바",
                      focus: "등·팔", pattern: "verticalPull", difficulty: 3,
                      cues: ["바를 잡고 몸통을 안정적으로 유지하세요.", "몸을 당겨 올린 뒤 천천히 내려오세요."],
                      mistake: "다리를 흔들어 반동을 만들지 않도록 해요.",
                      source: "https://www.nasm.org/workout-exercise-guidance")
    ]

    static func find(_ name: String) -> ExerciseGuide? {
        let key = AppData.exerciseKey(name)
        return all.first { guide in ([guide.name] + guide.aliases).contains { AppData.exerciseKey($0) == key } }
    }

    static func alternatives(for name: String, equipment: WorkoutEquipment?, reason: ReplacementReason) -> [ExerciseGuide] {
        guard let original = find(name) else { return [] }
        return all.filter {
            $0.id != original.id && $0.pattern == original.pattern
                && (equipment == nil || $0.equipment == equipment)
                && (reason != .difficult || $0.difficulty < original.difficulty)
                && (reason != .unavailable || $0.equipmentText != original.equipmentText)
        }.sorted { $0.difficulty < $1.difficulty }
    }
}

extension AppData {
    /// Split off completed sets before replacing the remainder. Prior journals and plans stay intact.
    /// Expected state guards a sheet left open while a widget or another device changes the workout.
    @discardableResult
    mutating func replaceExecutionExercise(_ original: Exercise, with replacement: Exercise, on date: Date,
                                          expectedSessionID: UUID?, expectedDone: Int) -> UUID? {
        guard !replacement.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              replacement.sets > 0, !replacement.hasPercentageTarget,
              activeWorkout?.id == expectedSessionID else { return nil }
        var plan = activeWorkout?.plan ?? self.plan(for: date)
        guard let index = plan.exercises.firstIndex(where: { $0.id == original.id }),
              plan.exercises[index] == original else { return nil }
        let done = activeWorkout.map { $0.doneSets(original) } ?? doneSets(original, on: date)
        guard done == expectedDone, done < original.sets else { return nil }
        var next = replacement
        next.id = UUID()
        next.sets = original.sets - done
        if done > 0 {
            plan.exercises[index].sets = done
            plan.exercises.insert(next, at: index + 1)
        } else { plan.exercises[index] = next }
        if var session = activeWorkout {
            session.plan = plan
            session.completedSets[next.id.uuidString] = 0
            if done == 0 {
                session.completedSets.removeValue(forKey: original.id.uuidString)
                session.actualReps.removeValue(forKey: original.id.uuidString)
                session.actualWeights.removeValue(forKey: original.id.uuidString)
            }
            activeWorkout = session
        } else { scheduledPlans[DayKey.key(date)] = plan }
        let day = activeWorkout?.day ?? DayKey.key(date)
        if let index = logs.firstIndex(where: { $0.day == day }) {
            if done == 0 { logs[index].doneSets.removeValue(forKey: original.id.uuidString) }
            logs[index].doneSets[next.id.uuidString] = 0
        }
        return next.id
    }
}
