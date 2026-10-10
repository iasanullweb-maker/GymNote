import Foundation

enum WorkoutEquipment: String, CaseIterable, Identifiable {
    case bodyweight = "맨몸"
    case dumbbell = "덤벨"
    case gym = "헬스장 기구"
    var id: String { rawValue }
}

enum WorkoutExperience: String, CaseIterable, Identifiable {
    case beginner = "처음 시작해요"
    case regular = "꾸준히 하고 있어요"
    var id: String { rawValue }
}

enum StarterWorkouts {
    static func plan(equipment: WorkoutEquipment, experience: WorkoutExperience, minutes: Int) -> DayPlan {
        let names: [String]
        switch equipment {
        case .bodyweight: names = ["의자 스쿼트", "벽 푸쉬업", "글루트 브리지", "플랭크"]
        case .dumbbell: names = ["고블릿 스쿼트", "덤벨 플로어 프레스", "덤벨 로우", "덤벨 루마니안 데드리프트"]
        case .gym: names = ["레그 프레스", "체스트 프레스", "시티드 케이블 로우", "랫 풀다운"]
        }
        let sets = minutes <= 15 ? 2 : (minutes >= 45 ? 4 : 3)
        let count = minutes <= 15 ? 3 : 4
        let reps = experience == .beginner ? 8 : 10
        let exercises = names.prefix(count).map { name in
            Exercise(name: name, sets: sets, detail: name == "플랭크" ? "20초" : "\(reps)회")
        }
        return DayPlan(title: "\(equipment.rawValue) 기본 루틴 · \(minutes)분", exercises: exercises)
    }
}

extension AppData {
    /// Append a previewed routine to one day. New IDs prevent collisions with prior logs.
    @discardableResult
    mutating func appendStarterWorkout(_ routine: DayPlan, on date: Date) -> [UUID]? {
        guard !routine.isRestDay, activeWorkout?.day != DayKey.key(date) else { return nil }
        var plan = self.plan(for: date)
        if plan.isRestDay { plan.title = routine.title }
        let copies = routine.exercises.map { exercise -> Exercise in
            var copy = exercise
            copy.id = UUID()
            return copy
        }
        plan.exercises.append(contentsOf: copies)
        scheduledPlans[DayKey.key(date)] = plan
        return copies.map(\.id)
    }
}
