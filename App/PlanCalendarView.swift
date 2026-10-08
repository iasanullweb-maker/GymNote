import SwiftUI

struct PlanCalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.gymnoteCompactLayout) private var compact
    enum Content { case workout, daily, all, journal }
    @Binding var selectedDate: Date
    var content: Content = .workout
    var onShowDateDetails: ((Date) -> Void)?
    @State private var displayedMonth: Date
    private let weekdayOrder = [1, 2, 3, 4, 5, 6, 0]

    init(selectedDate: Binding<Date>, content: Content = .workout, onShowDateDetails: ((Date) -> Void)? = nil) {
        _selectedDate = selectedDate
        self.content = content
        self.onShowDateDetails = onShowDateDetails
        _displayedMonth = State(initialValue: selectedDate.wrappedValue)
    }

    var body: some View {
        let dates = DayKey.monthDates(containing: displayedMonth)
        let workoutsByDay = content == .journal ? Dictionary(grouping: model.data.workouts, by: \.day) : [:]
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("이전 달")
                Text(displayedMonth, format: .dateTime.year().month())
                    .font(compact ? .headline : .title.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.accessibilityLabel("다음 달")
                Spacer()
                Button("오늘") {
                    selectedDate = Date()
                    displayedMonth = selectedDate
                }
            }
            // 모든 주의 높이를 처음부터 측정해 스크롤 중 높이 추정을 막는다.
            Grid(alignment: .topLeading, horizontalSpacing: compact ? 2 : 6, verticalSpacing: compact ? 4 : 6) {
                GridRow {
                    ForEach(weekdayOrder, id: \.self) { index in
                        Text(DayKey.weekdayNames[index])
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(stride(from: 0, to: dates.count, by: 7)), id: \.self) { offset in
                    GridRow {
                        ForEach(Array(dates[offset..<min(offset + 7, dates.count)]), id: \.self) { date in
                            dayCell(date, workouts: workoutsByDay[DayKey.key(date)] ?? [])
                        }
                    }
                }
            }
            if compact, content != .journal {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDate, format: .dateTime.month().day().weekday())
                        .font(.subheadline.bold())
                    planContent(
                        exercises: content == .daily ? [] : model.data.plan(for: selectedDate).exercises,
                        dailyItems: content == .workout ? [] : model.data.dailyItems(on: selectedDate),
                        date: selectedDate
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selectedDate) { _, date in
            if !Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = date
            }
        }
    }

    private func moveMonth(by offset: Int) {
        let start = Calendar.current.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        displayedMonth = Calendar.current.date(byAdding: .month, value: offset, to: start) ?? start
    }

    private func dayCell(_ date: Date, workouts: [WorkoutSession]) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let inMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let today = Calendar.current.isDateInToday(date)
        let exercises = content == .daily || content == .journal ? [] : model.data.plan(for: date).exercises
        let dailyItems = content == .workout || content == .journal ? [] : model.data.dailyItems(on: date)
        let journalNames = Array(Set(workouts.flatMap { workout in
            workout.plan.exercises.filter { workout.doneSets($0) > 0 }.map(\.name)
        })).sorted()
        let summary = content == .journal
            ? "운동 일지 \(workouts.count)개, " + journalNames.joined(separator: ", ")
            : (exercises.map(\.name) + dailyItems.map(\.title)).joined(separator: ", ")
        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(Calendar.current.component(.day, from: date)))
                    .font(compact ? .body.bold() : .title3.bold())
                    .foregroundStyle(selected || today ? Color.orange : Color.primary)
                    .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                if compact {
                    compactContent(workouts: workouts, exercises: exercises, dailyItems: dailyItems)
                } else if content == .journal {
                    journalContent(workouts: workouts, names: journalNames)
                } else {
                    planContent(exercises: exercises, dailyItems: dailyItems, date: date)
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 3 : 6)
            .frame(maxWidth: .infinity, minHeight: compact ? 64 : 132, alignment: .topLeading)
            .background(selected ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.orange : Color.clear, lineWidth: 1.5)
            }
            .opacity(inMonth ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
                .onEnded { _ in
                    selectedDate = date
                    onShowDateDetails?(date)
                },
            including: onShowDateDetails == nil ? .none : .all
        )
        .accessibilityLabel(date.formatted(.dateTime.year().month().day()) + ", " + summary)
        .accessibilityHint(onShowDateDetails == nil ? "날짜 선택" : "길게 눌러 이 날짜의 모든 운동 기록 보기")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityActions {
            if let onShowDateDetails {
                Button("전체 운동 기록 보기") {
                    selectedDate = date
                    onShowDateDetails(date)
                }
            }
        }
    }

    @ViewBuilder
    private func compactContent(workouts: [WorkoutSession], exercises: [Exercise], dailyItems: [DailyItem]) -> some View {
        VStack(spacing: 2) {
            if content == .journal {
                if !workouts.isEmpty {
                    Text("\(workouts.count)회").foregroundStyle(.orange)
                }
            } else {
                if !exercises.isEmpty {
                    Text("운동\(exercises.count)").foregroundStyle(.orange)
                }
                if !dailyItems.isEmpty {
                    Text("일상\(dailyItems.count)").foregroundStyle(.teal)
                }
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func journalContent(workouts: [WorkoutSession], names: [String]) -> some View {
        if workouts.isEmpty {
            Text("기록 없음").font(.system(size: 14)).foregroundStyle(.secondary)
        } else {
            let done = workouts.reduce(0) { $0 + $1.done }
            Text("\(workouts.count)회 · \(done)세트")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
            ForEach(names.prefix(3), id: \.self) { name in
                Text(name).font(.system(size: 14)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if names.count > 3 {
                Text("+\(names.count - 3)개 더").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planContent(exercises: [Exercise], dailyItems: [DailyItem], date: Date) -> some View {
        if exercises.isEmpty && dailyItems.isEmpty {
            Text(content == .workout ? "휴식" : "일정 없음")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        } else {
            ForEach(exercises) { exercise in
                Text(exercise.name).font(.system(size: 14)).foregroundStyle(.primary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        ForEach(dailyItems) { item in
            Text((model.data.isDailyComplete(item, on: date) ? "✓ " : "") + item.title)
                .font(.system(size: 14)).foregroundStyle(.teal).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("계획 캘린더") {
    PlanCalendarPreview()
}

private struct PlanCalendarPreview: View {
    @State private var selectedDate = Date()
    @State private var model = AppModel(previewData: AppData.sample)

    var body: some View {
        ScrollView {
            PlanCalendarView(selectedDate: $selectedDate)
                .padding()
        }
        .environment(model)
    }
}
