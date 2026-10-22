import SwiftUI

/// 실행 탭의 휴식 타이머. 애플 시계 앱 타이머처럼 분·초 휠로 시간을 고르고 둥근 버튼으로 시작/취소한다.
/// 휴식 중에는 휠 자리에 남은 시간 링이 돈다. 고른 시간은 '세트 사이 휴식'(AppData.defaultRest)이라
/// 세트 완료 때 자동으로 시작되는 휴식에도 그대로 쓰인다. (2026-10-22 사용자 요청: 기존 −/+ 제거)
struct RestTimerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dialHeight: CGFloat = 180

    var body: some View {
        // 휴식 중일 때만 시계를 돌린다(쉬는 동안 휠이 계속 다시 그려지지 않게).
        TimelineView(.animation(minimumInterval: 0.2, paused: model.restEnd == nil)) { context in
            let end = model.restEnd.flatMap { $0 > context.date ? $0 : nil }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    cancelButton(running: end != nil)
                    Spacer(minLength: 0)
                    dial(end: end, now: context.date)
                    Spacer(minLength: 0)
                    startButton(running: end != nil)
                }
                VStack(spacing: 12) {
                    dial(end: end, now: context.date)
                    HStack {
                        cancelButton(running: end != nil)
                        Spacer(minLength: 0)
                        startButton(running: end != nil)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: end != nil)
        }
        .padding(.vertical, 4)
    }

    // MARK: 가운데 — 휠 또는 남은 시간 링

    @ViewBuilder
    private func dial(end: Date?, now: Date) -> some View {
        if let end, let start = model.restStart {
            ring(start: start, end: end, now: now)
                .transition(.opacity)
        } else {
            wheels
                .transition(.opacity)
        }
    }

    private var wheels: some View {
        HStack(spacing: 0) {
            wheel(values: Array(0...SettingsView.restRange.upperBound / 60), selection: minutes, unit: "분")
            wheel(values: Array(0...59), selection: seconds, unit: "초")
        }
        .frame(height: Self.dialHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("세트 사이 휴식 시간")
    }

    private func wheel(values: [Int], selection: Binding<Int>, unit: String) -> some View {
        HStack(spacing: 4) {
            Picker(unit, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)").monospacedDigit().tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 72)
            .clipped()
            .accessibilityLabel(unit)
            Text(unit)
                .font(.headline)
                .accessibilityHidden(true)
        }
        .frame(height: Self.dialHeight)
    }

    private func ring(start: Date, end: Date, now: Date) -> some View {
        let total = max(end.timeIntervalSince(start), 1)
        let left = max(end.timeIntervalSince(now), 0)
        let fraction = min(max(left / total, 0), 1)
        let seconds = RestDuration.remaining(until: end, at: now)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
            VStack(spacing: 4) {
                Text(Self.clock(seconds))
                    .font(.system(size: 44, weight: .light).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 16)
        }
        .frame(width: Self.dialHeight, height: Self.dialHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("휴식 중")
        .accessibilityValue("\(RestDuration.text(seconds: seconds)) 남음")
    }

    // MARK: 둥근 버튼

    private func cancelButton(running: Bool) -> some View {
        Button("취소") { model.stopRest() }
            .buttonStyle(RoundTimerButtonStyle(fill: Color.secondary.opacity(0.22), text: .primary))
            .disabled(!running)
            .accessibilityLabel("휴식 취소")
    }

    private func startButton(running: Bool) -> some View {
        Button(running ? "재시작" : "시작") { model.startDefaultRest() }
            .buttonStyle(RoundTimerButtonStyle(fill: .orange, text: .black))
            .accessibilityLabel(running ? "휴식 다시 시작" : "휴식 \(RestDuration.text(seconds: model.data.defaultRest)) 시작")
    }

    // MARK: 값

    private var minutes: Binding<Int> {
        Binding(get: { model.data.defaultRest / 60 },
                set: { model.setDefaultRest(minutes: $0, seconds: model.data.defaultRest % 60) })
    }

    private var seconds: Binding<Int> {
        Binding(get: { model.data.defaultRest % 60 },
                set: { model.setDefaultRest(minutes: model.data.defaultRest / 60, seconds: $0) })
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 시계 앱 타이머의 둥근 시작/취소 버튼: 채운 원 + 바깥의 얇은 테두리 고리.
struct RoundTimerButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color
    var diameter: CGFloat = 76
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(text)
            .padding(8)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill).padding(4))
            .overlay(Circle().strokeBorder(fill, lineWidth: 2))
            .contentShape(Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
