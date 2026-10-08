import SwiftUI

struct PlanCalendarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDate: Date
    @State private var displayedMonth = Date()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 7)
    private let weekdayOrder = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }.accessibilityLabel("이전 달")
                Text(displayedMonth, format: .dateTime.year().month())
                    .font(.title2.bold())
                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }.accessibilityLabel("다음 달")
                Spacer()
                Button("오늘") {
                    selectedDate = Date()
                    displayedMonth = selectedDate
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayOrder, id: \.self) { index in
                    Text(DayKey.weekdayNames[index])
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(DayKey.monthDates(containing: displayedMonth), id: \.self) { date in
                    dayCell(date)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { displayedMonth = selectedDate }
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

    private func dayCell(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let inMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let today = Calendar.current.isDateInToday(date)
        let exercises = model.data.plan(for: date).exercises
        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(date, format: .dateTime.day())
                    .font(.headline)
                    .foregroundStyle(selected || today ? Color.orange : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if exercises.isEmpty {
                    Text("휴식")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(exercises) { exercise in
                        Text(exercise.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(selected ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.orange : Color.clear, lineWidth: 1.5)
            }
            .opacity(inMonth ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(date.formatted(.dateTime.year().month().day()) + ", " + (exercises.isEmpty ? "휴식" : exercises.map(\.name).joined(separator: ", ")))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
