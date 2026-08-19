import SwiftUI
import SwiftData
import HealthKit
import PhotosUI
import PDFKit
import UIKit
@preconcurrency import Vision
import UniformTypeIdentifiers
import Charts

@main
struct JourneyFitApp: App {
    private let container: ModelContainer = {
        let schema = Schema([StrengthWorkout.self, LiftSet.self, InBodyReport.self, InBodyMeasurement.self, GeneratedReport.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}

// MARK: - Stored workout data

@Model
final class StrengthWorkout {
    var id: UUID = UUID()
    var startedAt: Date
    var loggedAt: Date = Date.now
    var note: String
    @Relationship(deleteRule: .cascade, inverse: \LiftSet.workout) var sets: [LiftSet] = []

    init(id: UUID = UUID(), startedAt: Date = .now, loggedAt: Date = Date.now, note: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.loggedAt = loggedAt
        self.note = note
    }

    var volume: Double { sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }
}

@Model
final class LiftSet {
    var id: UUID = UUID()
    var loggedOrder: Int = 0
    var exercise: String
    var muscleGroup: String
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
    var takenToFailure: Bool = false
    var workout: StrengthWorkout?

    init(id: UUID = UUID(), loggedOrder: Int = 0, exercise: String, muscleGroup: String, weightKg: Double, reps: Int, rpe: Double? = nil, isWarmup: Bool = false, takenToFailure: Bool = false) {
        self.id = id
        self.loggedOrder = loggedOrder
        self.exercise = exercise
        self.muscleGroup = muscleGroup
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.takenToFailure = takenToFailure
    }

    var volume: Double { weightKg * Double(reps) }
}

@Model
final class InBodyReport {
    var id: UUID = UUID()
    var createdAt: Date
    var localFilename: String
    var displayName: String

    init(id: UUID = UUID(), createdAt: Date = .now, localFilename: String, displayName: String) {
        self.id = id
        self.createdAt = createdAt
        self.localFilename = localFilename
        self.displayName = displayName
    }
}

/// Imported InBody images are preserved unchanged. Recognition is used only to
/// prefill a separate, user-confirmed measurement record for Progress.
@Model
final class InBodyMeasurement {
    var id: UUID = UUID()
    var measuredAt: Date
    var weightKg: Double
    var bodyFatPercent: Double
    var visceralFatLevel: Double
    var bmi: Double

    init(id: UUID = UUID(), measuredAt: Date = .now, weightKg: Double, bodyFatPercent: Double, visceralFatLevel: Double, bmi: Double) {
        self.id = id
        self.measuredAt = measuredAt
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.visceralFatLevel = visceralFatLevel
        self.bmi = bmi
    }
}

@Model
final class GeneratedReport {
    var id: UUID = UUID()
    var createdAt: Date
    var localFilename: String
    var displayName: String

    init(id: UUID = UUID(), createdAt: Date = .now, localFilename: String, displayName: String) {
        self.id = id
        self.createdAt = createdAt
        self.localFilename = localFilename
        self.displayName = displayName
    }
}

enum ExerciseCatalog {
    static let items: [(String, String)] = [
        ("Chest Press", "Chest"), ("Dumbbell Incline Press", "Chest"), ("Pec Fly", "Chest"), ("Chest Raises", "Chest"),
        ("Pulley Tricep Pushdown", "Triceps"), ("Single Back Dumbbell Extension", "Triceps"), ("Skull Crushers", "Triceps"), ("Dumbbell Overhead Triceps Extension", "Triceps"),
        ("Bent Over Barbell Row", "Back"), ("RDL", "Back"), ("Lateral Pull Down", "Back"), ("1 Arm Rows", "Back"),
        ("Wide-Grip Barbell Curl", "Biceps"), ("Close-Grip Barbell Curl", "Biceps"), ("Zottman Curl", "Biceps"), ("Waiter Curl", "Biceps"), ("Cross Hammer Curl", "Biceps"),
        ("Reverse Barbell Press", "Forearms"), ("Pulley Forearm Pushdown", "Forearms"), ("Behind Back Barbell Wrist Twist", "Forearms"), ("Wrist Twists", "Forearms"),
        ("Shoulder Press", "Shoulders"), ("Side Lateral Raise", "Shoulders"),
        ("Leg Press", "Legs"), ("Calf Raises", "Legs"), ("Leg Curl", "Legs"), ("Dumbbell Squat", "Legs")
    ]

    static let muscleGroups = Array(Set(items.map(\.1))).sorted()
    static func exercises(for muscleGroup: String) -> [String] {
        items.filter { $0.1 == muscleGroup }.map(\.0)
    }
}

struct TemplateExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var muscleGroup: String
    var exercise: String
}

struct WorkoutTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var subtitle: String
    var exercises: [TemplateExercise]
    var isBuiltIn = false

    static let betaTemplates: [WorkoutTemplate] = [
        WorkoutTemplate(name: "Push", subtitle: "Chest, shoulders and triceps", exercises: [TemplateExercise(muscleGroup: "Chest", exercise: "Chest Press"), TemplateExercise(muscleGroup: "Shoulders", exercise: "Shoulder Press"), TemplateExercise(muscleGroup: "Triceps", exercise: "Pulley Tricep Pushdown")], isBuiltIn: true),
        WorkoutTemplate(name: "Pull", subtitle: "Back and biceps", exercises: [TemplateExercise(muscleGroup: "Back", exercise: "Bent Over Barbell Row"), TemplateExercise(muscleGroup: "Back", exercise: "RDL"), TemplateExercise(muscleGroup: "Biceps", exercise: "Wide-Grip Barbell Curl")], isBuiltIn: true),
        WorkoutTemplate(name: "Upper", subtitle: "Balanced upper body", exercises: [TemplateExercise(muscleGroup: "Chest", exercise: "Dumbbell Incline Press"), TemplateExercise(muscleGroup: "Back", exercise: "Lateral Pull Down"), TemplateExercise(muscleGroup: "Shoulders", exercise: "Side Lateral Raise"), TemplateExercise(muscleGroup: "Biceps", exercise: "Close-Grip Barbell Curl")], isBuiltIn: true),
        WorkoutTemplate(name: "Lower", subtitle: "Legs and calves", exercises: [TemplateExercise(muscleGroup: "Legs", exercise: "Leg Press"), TemplateExercise(muscleGroup: "Legs", exercise: "Leg Curl"), TemplateExercise(muscleGroup: "Legs", exercise: "Calf Raises")], isBuiltIn: true)
    ]
}

// MARK: - HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    @Published var permissionRequested = false
    @Published var weeklySteps = 0
    @Published var weeklyWorkoutCount = 0
    @Published var weeklyWorkoutMinutes = 0
    @Published var lastRefreshedAt: Date?
    @Published var errorMessage: String?
    private let store = HKHealthStore()

    static func mondayThroughSunday(containing date: Date = .now) -> DateInterval {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // Sunday = 1
        let daysSinceMonday = (weekday + 5) % 7
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysSinceMonday, to: date)!)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is not available on this device."
            return
        }
        do {
            let steps = HKObjectType.quantityType(forIdentifier: .stepCount)!
            let workouts = HKObjectType.workoutType()
            try await store.requestAuthorization(toShare: [], read: [steps, workouts])
            permissionRequested = true
            await refreshCurrentWeek()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshCurrentWeek() async {
        let interval = Self.mondayThroughSunday()
        do {
            let types: Set<HKObjectType> = [HKObjectType.quantityType(forIdentifier: .stepCount)!, HKObjectType.workoutType()]
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: types)
            if status == .shouldRequest {
                // The system sheet is shown only until the first request. Once handled,
                // subsequent launches simply refresh the saved HealthKit permission state.
                await requestAuthorization()
                return
            }
            permissionRequested = true
            let summary = try await summary(in: interval)
            weeklySteps = summary.steps
            weeklyWorkoutCount = summary.workoutCount
            weeklyWorkoutMinutes = summary.workoutMinutes
            lastRefreshedAt = .now
        } catch { errorMessage = "Unable to load Health data. Check permissions in Health." }
    }

    func summary(in interval: DateInterval) async throws -> (steps: Int, workoutCount: Int, workoutMinutes: Int) {
        async let steps = readSteps(in: interval)
        async let workouts = readWorkouts(in: interval)
        let records = try await workouts
        return (try await steps, records.count, Int(records.reduce(0) { $0 + $1.duration } / 60))
    }

    func readDailySteps(in interval: DateInterval) async throws -> [(date: Date, steps: Int)] {
        var values: [(Date, Int)] = []
        var day = Calendar.current.startOfDay(for: interval.start)
        while day < interval.end {
            let end = min(Calendar.current.date(byAdding: .day, value: 1, to: day)!, interval.end)
            values.append((day, try await readSteps(in: DateInterval(start: day, end: end))))
            day = end
        }
        return values
    }

    func readSteps(in interval: DateInterval) async throws -> Int {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            store.execute(query)
        }
    }

    func readWorkouts(in interval: DateInterval) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }
}

enum AppleAppNavigator {
    static func openSteps() { UIApplication.shared.open(URL(string: "x-apple-health://SampleType/HKQuantityTypeIdentifierStepCount")!) }
    static func openFitness() { UIApplication.shared.open(URL(string: "fitnessapp:root=WORKOUT")!) }
}

// MARK: - App shell (personal, no-account mode)

struct RootView: View {
    var body: some View {
        AppTabView()
    }
}

private enum AppTab: Hashable {
    case today, log, progress, reports, profile
}

struct AppTabView: View {
    @StateObject private var health = HealthKitManager()
    @State private var selectedTab: AppTab = .today
    @State private var requestedWorkoutID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(startWorkout: { selectedTab = .log })
                .tabItem { Label("Today", systemImage: "house.fill") }.tag(AppTab.today)
            WorkoutLogView(requestedWorkoutID: $requestedWorkoutID)
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }.tag(AppTab.log)
            ProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(AppTab.progress)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "doc.richtext") }.tag(AppTab.reports)
            SettingsView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(AppTab.profile)
        }
        .environmentObject(health)
        .tint(JourneyFitTheme.accent)
    }
}

enum JourneyFitTheme {
    static let accent = Color.accentColor
    static let success = Color.green
    static let background = Color(uiColor: .systemGroupedBackground)
    static let ink = Color.primary
    static let muted = Color.secondary
}

enum WeekCalendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

struct JourneyFitCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StrengthWorkout.startedAt, order: .reverse) private var strengthWorkouts: [StrengthWorkout]
    @State private var startDate = HealthKitManager.mondayThroughSunday().start
    @State private var endDate = HealthKitManager.mondayThroughSunday().end.addingTimeInterval(-1)
    @State private var displayedSteps = 0
    @State private var displayedWorkoutCount = 0
    @State private var isCustomPeriod = false
    @State private var showingPeriodPicker = false
    let startWorkout: () -> Void

    private var selectedInterval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: startDate), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!)
    }

    private var periodTitle: String {
        isCustomPeriod ? "Custom period · \(startDate.formatted(date: .abbreviated, time: .omitted))–\(endDate.formatted(date: .abbreviated, time: .omitted))" : "This week · \(startDate.formatted(date: .abbreviated, time: .omitted))–\(endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyFitTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack(spacing: 12) {
                            Image(uiImage: UIImage(named: "JourneyFitLogo") ?? UIImage())
                                .resizable().scaledToFit().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) { Text("JourneyFit").font(.title2.weight(.bold)); Text("Today").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        HStack {
                            Text(periodTitle).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button { showingPeriodPicker = true } label: { Label("Change", systemImage: "calendar").font(.subheadline.weight(.semibold)) }.buttonStyle(.bordered)
                        }
                        if health.permissionRequested {
                            HStack(spacing: 22) {
                                Button { AppleAppNavigator.openSteps() } label: { WeeklyActivityRing(progress: min(Double(displayedSteps) / 70_000, 1), color: .pink, value: displayedSteps.formatted(), label: "STEPS") }
                                Button { AppleAppNavigator.openFitness() } label: { WeeklyActivityRing(progress: min(Double(displayedWorkoutCount) / 7, 1), color: .green, value: "\(displayedWorkoutCount)", label: "WORKOUTS") }
                            }.frame(maxWidth: .infinity)
                            HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Apple Health connected") }
                                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Button { Task { await health.requestAuthorization() } } label: { Label("Connect Apple Health", systemImage: "heart.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.borderedProminent).tint(.pink)
                        }
                        JourneyFitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("TRAINING", systemImage: "figure.strengthtraining.traditional").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(JourneyFitTheme.muted)
                                Text(strengthWorkouts.isEmpty ? "Ready for your first workout?" : "Ready to train?").font(.title3.weight(.bold))
                                Text(strengthWorkouts.isEmpty ? "Log each set as you go and JourneyFit will build your progress history." : "Start a fresh session or continue logging today’s workout.").font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                                Button(action: startWorkout) { Label(strengthWorkouts.isEmpty ? "Start workout" : "Open workout log", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 5) }
                                    .buttonStyle(.borderedProminent).tint(JourneyFitTheme.accent)
                            }
                        }
                        if !trainingInsights.isEmpty {
                            JourneyFitCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("TRAINING INSIGHTS", systemImage: "chart.line.uptrend.xyaxis")
                                        .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(JourneyFitTheme.muted)
                                    ForEach(trainingInsights) { insight in
                                        Label(insight.message, systemImage: insight.symbol)
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(JourneyFitTheme.ink)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
                }
            }
            .task { await loadDashboardData() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await loadDashboardData() }
            }
            .refreshable { await loadDashboardData() }
            .sheet(isPresented: $showingPeriodPicker) {
                DashboardPeriodPicker(startDate: $startDate, endDate: $endDate) { useCurrentWeek in
                    isCustomPeriod = !useCurrentWeek
                    Task { await loadDashboardData() }
                }.presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func loadDashboardData() async {
        await health.refreshCurrentWeek()
        guard health.permissionRequested else { return }
        if !isCustomPeriod {
            let week = HealthKitManager.mondayThroughSunday()
            startDate = week.start
            endDate = week.end.addingTimeInterval(-1)
            displayedSteps = health.weeklySteps
            displayedWorkoutCount = health.weeklyWorkoutCount
        }
        let summary = try? await health.summary(in: selectedInterval)
        if let summary {
            displayedSteps = summary.steps
            displayedWorkoutCount = summary.workoutCount
        }
    }

    private struct TrainingInsight: Identifiable {
        let id: String
        let message: String
        let symbol: String
    }

    private var trainingInsights: [TrainingInsight] {
        let ordered = strengthWorkouts.sorted { $0.loggedAt > $1.loggedAt }
        guard let latest = ordered.first else { return [] }
        var seen = Set<String>()
        let exercises = latest.sets.sorted { $0.loggedOrder < $1.loggedOrder }.map(\.exercise).filter { seen.insert($0).inserted }
        return exercises.map { exercise in
            let currentSets = latest.sets.filter { $0.exercise == exercise }
            guard let previous = ordered.dropFirst().first(where: { $0.sets.contains(where: { $0.exercise == exercise }) }) else {
                return TrainingInsight(id: exercise, message: "\(exercise): first logged session—your baseline is set.", symbol: "flag.checkered")
            }
            let currentReps = currentSets.reduce(0) { $0 + $1.reps }
            let previousReps = previous.sets.filter { $0.exercise == exercise }.reduce(0) { $0 + $1.reps }
            let currentWeight = currentSets.map(\.weightKg).max() ?? 0
            let previousWeight = previous.sets.filter { $0.exercise == exercise }.map(\.weightKg).max() ?? 0
            if currentWeight > previousWeight {
                return TrainingInsight(id: exercise, message: "\(exercise): +\((currentWeight - previousWeight).formatted()) kg vs your previous session.", symbol: "arrow.up.right")
            }
            let delta = currentReps - previousReps
            return TrainingInsight(id: exercise, message: delta == 0 ? "\(exercise): matched your previous session." : "\(exercise): \(delta > 0 ? "+" : "")\(delta) reps vs your previous session.", symbol: delta >= 0 ? "chart.line.uptrend.xyaxis" : "arrow.down.right")
        }
    }
}

struct LiftingProgressDashboard: View {
    let workouts: [StrengthWorkout]
    var sessionLimit: Int? = 5
    @State private var selectedMuscleGroup: String?
    @State private var selectedExercise: String?
    @State private var metric: ProgressMetric = .totalReps

    private enum ProgressMetric: String, CaseIterable, Identifiable {
        case totalReps = "Total reps"
        case weight = "Weight"
        var id: String { rawValue }
        var chartTitle: String { self == .weight ? "Weight (kg)" : rawValue }
    }

    private struct ProgressPoint: Identifiable {
        let id: UUID
        let date: Date
        let weight: Double
        let totalReps: Int
    }

    private var muscleGroups: [String] { Array(Set(workouts.flatMap(\.sets).map(\.muscleGroup))).sorted() }
    private var activeMuscleGroup: String? { selectedMuscleGroup.flatMap { muscleGroups.contains($0) ? $0 : nil } ?? muscleGroups.first }
    private var exercises: [String] {
        guard let activeMuscleGroup else { return [] }
        return Array(Set(workouts.flatMap(\.sets).filter { $0.muscleGroup == activeMuscleGroup }.map(\.exercise))).sorted()
    }
    private var activeExercise: String? { selectedExercise.flatMap { exercises.contains($0) ? $0 : nil } ?? exercises.first }
    private var points: [ProgressPoint] {
        guard let activeExercise else { return [] }
        return workouts
            .filter { $0.sets.contains(where: { $0.exercise == activeExercise }) }
            .sorted { $0.loggedAt < $1.loggedAt }
            .map { workout in
                let sets = workout.sets.filter { $0.exercise == activeExercise }
                return ProgressPoint(id: workout.id, date: workout.startedAt, weight: sets.map(\.weightKg).max() ?? 0, totalReps: sets.reduce(0) { $0 + $1.reps })
            }
    }

    private var displayedPoints: [ProgressPoint] {
        guard let sessionLimit else { return points }
        return Array(points.suffix(sessionLimit))
    }

    private func valueText(for point: ProgressPoint) -> String {
        metric == .weight ? "\(point.weight.formatted()) kg" : "\(point.totalReps) reps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sessionLimit == nil ? "LIFTING PROGRESS" : "RECENT LIFTING PROGRESS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(JourneyFitTheme.muted)
            HStack(spacing: 10) {
                Picker("Muscle group", selection: $selectedMuscleGroup) {
                    Text("Choose group").tag(Optional<String>.none)
                    ForEach(muscleGroups, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedMuscleGroup) { _, _ in selectedExercise = nil }

                Picker("Exercise", selection: $selectedExercise) {
                    Text("Choose exercise").tag(Optional<String>.none)
                    ForEach(exercises, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(JourneyFitTheme.accent)
            if displayedPoints.isEmpty {
                JourneyFitCard { Text("Log a strength workout to see your progress over time.").font(.subheadline).foregroundStyle(JourneyFitTheme.muted) }
            } else {
                JourneyFitCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Metric", selection: $metric) { ForEach(ProgressMetric.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        Text(sessionLimit == nil ? "\(displayedPoints.count) logged session\(displayedPoints.count == 1 ? "" : "s") in this period" : "Latest \(displayedPoints.count) logged session\(displayedPoints.count == 1 ? "" : "s")").font(.caption.weight(.semibold)).foregroundStyle(JourneyFitTheme.muted)
                        Chart(displayedPoints) { point in
                            LineMark(x: .value("Session", point.date), y: .value(metric.chartTitle, metric == .weight ? point.weight : Double(point.totalReps)))
                                .foregroundStyle(JourneyFitTheme.accent).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            PointMark(x: .value("Session", point.date), y: .value(metric.chartTitle, metric == .weight ? point.weight : Double(point.totalReps)))
                                .foregroundStyle(JourneyFitTheme.accent).symbolSize(36)
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    Text(valueText(for: point)).font(.caption2.weight(.bold)).foregroundStyle(JourneyFitTheme.ink)
                                }
                        }
                        .chartXAxis { AxisMarks(values: displayedPoints.map(\.date)) { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 190)
                    }
                }
            }
        }
    }
}

private enum ProgressRange: String, CaseIterable, Identifiable {
    case fourWeeks = "4W"
    case twelveWeeks = "12W"
    case allTime = "All"
    var id: String { rawValue }
    var dayCount: Int? {
        switch self {
        case .fourWeeks: return 28
        case .twelveWeeks: return 84
        case .allTime: return nil
        }
    }
}

struct ProgressView: View {
    @Query(sort: \StrengthWorkout.startedAt, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \InBodyMeasurement.measuredAt, order: .reverse) private var inBodyMeasurements: [InBodyMeasurement]
    @State private var range: ProgressRange = .twelveWeeks

    private var rangeWorkouts: [StrengthWorkout] {
        guard let days = range.dayCount,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return workouts }
        return workouts.filter { $0.startedAt >= cutoff }
    }

    private var rangeInBodyMeasurements: [InBodyMeasurement] {
        guard let days = range.dayCount,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return inBodyMeasurements }
        return inBodyMeasurements.filter { $0.measuredAt >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyFitTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("PROGRESS").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(JourneyFitTheme.accent)
                        Text("See the work\nadd up.").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(JourneyFitTheme.ink)
                        Picker("Progress range", selection: $range) {
                            ForEach(ProgressRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        JourneyFitCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(range == .allTime ? "All recorded sessions" : "Last \(range.dayCount ?? 0) days")
                                    .font(.headline)
                                Text("Choose an exercise to compare reps and working weight over time.")
                                    .font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                            }
                        }
                        LiftingProgressDashboard(workouts: rangeWorkouts, sessionLimit: 5)
                        InBodyProgressDashboard(measurements: rangeInBodyMeasurements)
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct InBodyProgressDashboard: View {
    @Environment(\.modelContext) private var context
    enum Metric: String, CaseIterable, Identifiable {
        case weight = "Weight"
        case bodyFat = "Body fat %"
        case visceralFat = "Visceral fat"
        case bmi = "BMI"
        var id: String { rawValue }
        var unit: String { self == .weight ? "kg" : self == .bodyFat ? "%" : "" }
    }

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    let measurements: [InBodyMeasurement]
    @State private var metric: Metric = .weight
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var detectedValues: InBodyDetectedValues?
    @State private var importMessage: String?

    private var points: [Point] {
        measurements.sorted { $0.measuredAt < $1.measuredAt }.map {
            Point(id: $0.id, date: $0.measuredAt, value: value(for: $0))
        }
    }

    private var latest: InBodyMeasurement? { measurements.max { $0.measuredAt < $1.measuredAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INBODY PROGRESS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(JourneyFitTheme.muted)
                Spacer()
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Import report", systemImage: "photo.badge.plus").font(.caption.weight(.semibold))
                }
            }
            JourneyFitCard {
                if points.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No measurements yet").font(.headline)
                        Text("Import an InBody report here. JourneyFit reads the result and asks you to confirm it before adding the trend.")
                            .font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("InBody metric", selection: $metric) {
                            ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu)
                        if let latest {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Latest").font(.caption.weight(.semibold)).foregroundStyle(JourneyFitTheme.muted)
                                    Text("\(value(for: latest).formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)")
                                        .font(.title3.weight(.bold))
                                }
                                Spacer()
                                Text(category(for: latest)).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(categoryColor(for: latest).opacity(0.14), in: Capsule()).foregroundStyle(categoryColor(for: latest))
                            }
                        }
                        Chart(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                .foregroundStyle(JourneyFitTheme.accent).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                .foregroundStyle(JourneyFitTheme.accent)
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    Text("\(point.value.formatted(.number.precision(.fractionLength(0...1))))\(metric.unit)").font(.caption2.weight(.bold))
                                }
                        }
                        .chartXAxis { AxisMarks(values: points.map(\.date)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 190)
                        Text(categoryExplanation).font(.caption).foregroundStyle(JourneyFitTheme.muted)
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in Task { await importReport(item) } }
        .sheet(item: $detectedValues) { values in InBodyMeasurementEditor(detectedValues: values).presentationDetents([.large]) }
        .alert("InBody import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(importMessage ?? "") }
    }

    private func importReport(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        defer { selectedPhoto = nil }
        if let url = try? InBodyStorage.save(data: data) {
            context.insert(InBodyReport(localFilename: url.lastPathComponent, displayName: "InBody report · \(Date.now.formatted(date: .abbreviated, time: .omitted))"))
            try? context.save()
        }
        guard let values = await InBodyReportReader.read(data), values.weightKg != nil || values.bodyFatPercent != nil || values.visceralFatLevel != nil || values.bmi != nil else {
            importMessage = "JourneyFit could not read measurements from this image. Try a clear, uncropped InBody report."
            return
        }
        detectedValues = values
    }

    private func value(for measurement: InBodyMeasurement) -> Double {
        switch metric { case .weight: measurement.weightKg; case .bodyFat: measurement.bodyFatPercent; case .visceralFat: measurement.visceralFatLevel; case .bmi: measurement.bmi }
    }

    private func category(for measurement: InBodyMeasurement) -> String {
        switch metric {
        case .bmi:
            switch measurement.bmi { case ..<18.5: "Under"; case ..<25: "Normal"; case ..<30: "Over"; default: "High" }
        case .visceralFat:
            switch measurement.visceralFatLevel { case ...9: "Normal"; case ...14: "Over"; default: "High" }
        case .weight, .bodyFat: "Recorded"
        }
    }

    private func categoryColor(for measurement: InBodyMeasurement) -> Color {
        category(for: measurement) == "Normal" || category(for: measurement) == "Recorded" ? JourneyFitTheme.success : .orange
    }

    private var categoryExplanation: String {
        switch metric {
        case .bmi: "BMI category: Under < 18.5 · Normal 18.5–24.9 · Over 25–29.9 · High ≥ 30."
        case .visceralFat: "Visceral-fat category: Normal 1–9 · Over 10–14 · High 15+."
        case .weight: "Weight has no universal under/normal/over category without personal targets."
        case .bodyFat: "Body-fat ranges depend on age and sex, so the result is shown without a generic category."
        }
    }
}

struct InBodyDetectedValues: Identifiable {
    let id = UUID()
    let weightKg: Double?
    let bodyFatPercent: Double?
    let visceralFatLevel: Double?
    let bmi: Double?
    var isComplete: Bool { weightKg != nil && bodyFatPercent != nil && visceralFatLevel != nil && bmi != nil }
}

struct InBodyMeasurementEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var weightKg: Double
    @State private var bodyFatPercent: Double
    @State private var visceralFatLevel: Double
    @State private var bmi: Double
    let detectedValues: InBodyDetectedValues

    init(detectedValues: InBodyDetectedValues) {
        self.detectedValues = detectedValues
        _weightKg = State(initialValue: detectedValues.weightKg ?? 0)
        _bodyFatPercent = State(initialValue: detectedValues.bodyFatPercent ?? 0)
        _visceralFatLevel = State(initialValue: detectedValues.visceralFatLevel ?? 0)
        _bmi = State(initialValue: detectedValues.bmi ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(detectedValues.isComplete ? "READ FROM YOUR INBODY REPORT" : "CHECK THE DETECTED INBODY VALUES") {
                    DatePicker("Measurement date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    TextField("Weight (kg)", value: $weightKg, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad)
                    TextField("Body fat (%)", value: $bodyFatPercent, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad)
                    TextField("Visceral fat level", value: $visceralFatLevel, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad)
                    TextField("BMI", value: $bmi, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad)
                }
                Section { Text(detectedValues.isComplete ? "JourneyFit read these values from the imported report. Confirm them before saving the trend." : "Some values could not be confidently read. Correct the highlighted values from the imported report before saving.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Log InBody result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { context.insert(InBodyMeasurement(measuredAt: date, weightKg: weightKg, bodyFatPercent: bodyFatPercent, visceralFatLevel: visceralFatLevel, bmi: bmi)); try? context.save(); dismiss() } }
            }
        }
    }
}

struct DashboardPeriodPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("CUSTOM DATE RANGE") {
                    DatePicker("From", selection: $startDate, in: Date(timeIntervalSince1970: 0)...endDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, in: startDate...Calendar.current.startOfDay(for: .now), displayedComponents: .date)
                }
                Section { Button("Use current week (Mon–Sun)") { let week = HealthKitManager.mondayThroughSunday(); startDate = week.start; endDate = week.end.addingTimeInterval(-1); onApply(true); dismiss() } }
            }
            .navigationTitle("Dashboard period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply(false); dismiss() } }
            }
        }
        .environment(\.calendar, WeekCalendar.mondayFirst)
    }
}

struct WeeklyActivityRing: View {
    let progress: Double
    let color: Color
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.20), lineWidth: 12)
                Circle().trim(from: 0, to: max(progress, 0.02)).stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(value).font(.title3.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
            }.frame(width: 122, height: 122)
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
        }
    }
}

struct MuscleGroupDashboard: View {
    let workouts: [StrengthWorkout]
    private var groups: [(String, Int)] {
        Dictionary(grouping: workouts.flatMap(\.sets), by: \.muscleGroup)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0 < $1.0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MUSCLE GROUPS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            Text("Your training split").font(.title2.weight(.bold))
            if groups.isEmpty {
                Text("Log a workout to see the muscle groups you trained this week.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.orange)
                            Text(group.0).font(.headline)
                            Text("\(group.1) sets logged").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}

struct DoubleProgressionSection: View {
    let workouts: [StrengthWorkout]

    private struct LatestExerciseSession: Identifiable {
        let exercise: String
        let workout: StrengthWorkout
        let sets: [LiftSet]
        var id: String { exercise }
    }

    private var latestSessions: [LatestExerciseSession] {
        var seen = Set<String>()
        var items: [LatestExerciseSession] = []
        for workout in workouts.sorted(by: { $0.startedAt > $1.startedAt }) {
            for exercise in Set(workout.sets.map(\.exercise)) where !seen.contains(exercise) {
                let sets = workout.sets.filter { $0.exercise == exercise }
                guard !sets.isEmpty else { continue }
                seen.insert(exercise)
                items.append(LatestExerciseSession(exercise: exercise, workout: workout, sets: sets))
            }
        }
        return items.sorted { $0.exercise < $1.exercise }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOUBLE PROGRESSION").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            Text("Build strength with intent.").font(.title3.weight(.bold))
            Text("4 working sets · 10–12 reps per set · increase weight when every set reaches 10 reps.")
                .font(.footnote).foregroundStyle(.secondary)
            if latestSessions.isEmpty {
                JourneyFitCard { ContentUnavailableView("No working sets yet", systemImage: "arrow.up.right.circle", description: Text("Log four working sets for an exercise to see its next step.")) }
            }
            ForEach(latestSessions) { item in
                DoubleProgressionCard(exercise: item.exercise, session: item.workout, sets: item.sets, workouts: workouts)
            }
        }
    }
}

struct DoubleProgressionCard: View {
    let exercise: String
    let session: StrengthWorkout
    let sets: [LiftSet]
    let workouts: [StrengthWorkout]
    private let workingSetCount = 4
    private let targetMinimum = 10

    private var currentSets: [LiftSet] { Array(sets.prefix(workingSetCount)) }
    private var currentLoad: Double { currentSets.map(\.weightKg).max() ?? 0 }
    private var readyToIncrease: Bool { currentSets.count == workingSetCount && currentSets.allSatisfy { $0.reps >= targetMinimum } }
    private var priorSets: [LiftSet] {
        for workout in workouts.sorted(by: { $0.startedAt > $1.startedAt }) where workout.startedAt < session.startedAt {
            let prior = workout.sets.filter { $0.exercise == exercise }
            if !prior.isEmpty { return Array(prior.prefix(workingSetCount)) }
        }
        return []
    }
    private var status: (String, String, Color) {
        if readyToIncrease { return ("Increase load next session", "Every working set reached at least 10 reps at \(currentLoad.formatted()) kg.", .green) }
        if let previousLoad = priorSets.map(\.weightKg).max(), currentLoad > previousLoad { return ("New load — build reps", "Stay at \(currentLoad.formatted()) kg until every set reaches 10 reps.", .blue) }
        let improved = zip(currentSets, priorSets).filter { pair in pair.0.reps > pair.1.reps }.count
        if improved > 0 { return ("Build reps", "You improved reps in \(improved) of 4 comparable sets.", .orange) }
        return ("Build reps", "Keep \(currentLoad.formatted()) kg and work toward 10 reps in every set.", .orange)
    }

    var body: some View {
        JourneyFitCard {
            VStack(alignment: .leading, spacing: 12) {
            HStack { Text(exercise).font(.headline.weight(.bold)).foregroundStyle(JourneyFitTheme.ink); Spacer(); Text("\(currentLoad.formatted()) kg").font(.headline.weight(.bold)).foregroundStyle(status.2) }
            HStack(spacing: 6) {
                ForEach(0..<workingSetCount, id: \.self) { index in
                    VStack(spacing: 2) {
                        Text("Set \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                        if index < currentSets.count {
                            Text("\(currentSets[index].reps)").font(.headline)
                        } else { Text("—").font(.headline).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(status.2.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Text(status.0).font(.subheadline.bold()).foregroundStyle(status.2)
            Text(status.1).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Strength logging

struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Binding var requestedWorkoutID: UUID?
    @Query(sort: \StrengthWorkout.startedAt, order: .reverse) private var savedWorkouts: [StrengthWorkout]
    @State private var workout = StrengthWorkout()
    @State private var editor: SetEditor?
    @State private var savedMessage = false
    @State private var selectedDate: Date? = Calendar.current.startOfDay(for: .now)
    @State private var showingDatePicker = false
    @State private var showingAllSessions = false
    @State private var historyCalendarDate = Calendar.current.startOfDay(for: .now)
    @State private var isEditingSavedSession = false
    @State private var expandedExerciseIDs = Set<String>()
    @State private var showingTemplates = false

    private var exerciseGroups: [DraftExerciseGroup] {
        var orderedKeys: [String] = []
        var groups: [String: [LiftSet]] = [:]
        for set in workout.sets.sorted(by: { $0.loggedOrder < $1.loggedOrder }) {
            let key = "\(set.muscleGroup)|\(set.exercise)"
            if groups[key] == nil { orderedKeys.append(key) }
            groups[key, default: []].append(set)
        }
        return orderedKeys.compactMap { key in
            guard let values = groups[key], let first = values.first else { return nil }
            return DraftExerciseGroup(id: key, muscleGroup: first.muscleGroup, exercise: first.exercise, setIDs: values.map(\.id))
        }
    }

    private var savedWorkoutDays: [SavedWorkoutDay] {
        let calendar = Calendar.current
        var orderedDates: [Date] = []
        var grouped: [Date: [StrengthWorkout]] = [:]
        for session in savedWorkouts {
            let day = calendar.startOfDay(for: session.startedAt)
            if grouped[day] == nil { orderedDates.append(day) }
            grouped[day, default: []].append(session)
        }
        return orderedDates.compactMap { day in grouped[day].map { SavedWorkoutDay(date: day, workouts: $0) } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyFitTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("TRAIN").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(JourneyFitTheme.accent)
                        Text(isEditingSavedSession ? "Edit session." : "Log a session.").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(JourneyFitTheme.ink)
                        if isEditingSavedSession {
                            HStack {
                                Label("Editing a saved session", systemImage: "pencil.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(JourneyFitTheme.accent)
                                Spacer()
                                Button("Close") { closeSavedSession() }.buttonStyle(.bordered)
                            }
                        }
                        Button { showingDatePicker = true } label: {
                            HStack { Image(systemName: "calendar"); Text(selectedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Select workout date"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(JourneyFitTheme.accent).padding(16)
                                .background(JourneyFitTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        if !isEditingSavedSession {
                            HStack(spacing: 10) {
                                Button { showingTemplates = true } label: { Label("Use template", systemImage: "square.grid.2x2.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(.bordered).tint(JourneyFitTheme.accent)
                                Button { loadLastWorkout() } label: { Label("Repeat last", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                                    .buttonStyle(.bordered).tint(JourneyFitTheme.accent).disabled(savedWorkouts.isEmpty)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        HStack { Text("Exercises").font(.title3.weight(.bold)).foregroundStyle(JourneyFitTheme.ink); Spacer(); Text("\(exerciseGroups.count)").font(.subheadline.weight(.bold)).foregroundStyle(JourneyFitTheme.accent).padding(.horizontal, 10).padding(.vertical, 5).background(JourneyFitTheme.accent.opacity(0.12), in: Capsule()) }
                        if workout.sets.isEmpty {
                            JourneyFitCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(JourneyFitTheme.accent)
                                    Text("Add exercise").font(.headline)
                                    Text("Choose an exercise, then add and edit its individual sets.").font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                                    Button { editor = SetEditor(seed: nil, existingSet: nil, recentSets: recentSets) } label: { Label("Add exercise", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(JourneyFitTheme.accent)
                                }
                            }
                        } else {
                            ForEach(exerciseGroups) { group in
                                JourneyFitCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Button { toggleExercise(group.id) } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) { Text(group.exercise).font(.headline.weight(.bold)); Text(group.muscleGroup).font(.caption).foregroundStyle(JourneyFitTheme.muted) }
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 2) { Text("\(group.setIDs.count) sets · \(totalReps(for: group)) reps").font(.caption.weight(.bold)).foregroundStyle(JourneyFitTheme.accent); Image(systemName: expandedExerciseIDs.contains(group.id) ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(JourneyFitTheme.muted) }
                                            }
                                        }.buttonStyle(.plain)
                                        if isEditingSavedSession {
                                            HStack(spacing: 12) {
                                                Spacer()
                                                Button { moveExercise(group.id, earlier: true) } label: { Label("Move earlier", systemImage: "arrow.up") }
                                                    .buttonStyle(.bordered)
                                                    .disabled(exerciseGroups.first?.id == group.id)
                                                Button { moveExercise(group.id, earlier: false) } label: { Label("Move later", systemImage: "arrow.down") }
                                                    .buttonStyle(.bordered)
                                                    .disabled(exerciseGroups.last?.id == group.id)
                                            }
                                            .font(.caption.weight(.semibold))
                                            .tint(JourneyFitTheme.accent)
                                        }
                                        if expandedExerciseIDs.contains(group.id) {
                                            ForEach(displaySets(for: group)) { item in
                                                setRow(item.set, displayIndex: item.displayIndex, setID: item.id)
                                            }
                                        }
                                        Button {
                                            let previousSet = recentSets.first { $0.muscleGroup == group.muscleGroup && $0.exercise == group.exercise }
                                            editor = SetEditor(seed: ExerciseSeed(muscleGroup: group.muscleGroup, exercise: group.exercise, weightKg: previousSet?.weightKg, reps: previousSet?.reps), existingSet: nil, recentSets: recentSets)
                                        } label: { Label("Add set", systemImage: "plus") }.buttonStyle(.bordered).tint(JourneyFitTheme.accent)
                                    }
                                }
                            }
                            Button { editor = SetEditor(seed: nil, existingSet: nil, recentSets: recentSets) } label: { Label("Add another exercise", systemImage: "plus") }.buttonStyle(.bordered).tint(JourneyFitTheme.accent).frame(maxWidth: .infinity)
                        }
                        Button {
                            workout.startedAt = selectedDate ?? workout.startedAt
                            if !isEditingSavedSession {
                                workout.loggedAt = .now
                                if let existingSession = savedWorkouts
                                    .filter({ Calendar.current.isDate($0.startedAt, inSameDayAs: workout.startedAt) })
                                    .sorted(by: { $0.loggedAt < $1.loggedAt })
                                    .first {
                                    // A calendar day is one strength session. Keep the sets in the
                                    // order they were logged, while adding a later entry to that day.
                                    var nextOrder = (existingSession.sets.map(\.loggedOrder).max() ?? -1) + 1
                                    for set in workout.sets.sorted(by: { $0.loggedOrder < $1.loggedOrder }) {
                                        set.loggedOrder = nextOrder
                                        nextOrder += 1
                                    }
                                    existingSession.sets.append(contentsOf: workout.sets)
                                } else {
                                    context.insert(workout)
                                }
                            }
                            try? context.save()
                            workout = StrengthWorkout()
                            selectedDate = Calendar.current.startOfDay(for: .now)
                            isEditingSavedSession = false
                            savedMessage = true
                        } label: {
                            Label(isEditingSavedSession ? "Save changes" : "Save workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).font(.headline).padding(.vertical, 5)
                        }.buttonStyle(.borderedProminent).tint(JourneyFitTheme.accent).disabled(workout.sets.isEmpty || selectedDate == nil)
                        if !savedWorkoutDays.isEmpty {
                            HStack {
                                Text("RECENT SESSIONS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(JourneyFitTheme.muted)
                                Spacer()
                                Button("View calendar") { showingAllSessions = true }
                                    .font(.caption.weight(.semibold)).foregroundStyle(JourneyFitTheme.accent)
                            }
                            ForEach(Array(savedWorkoutDays.prefix(3))) { day in
                                savedSessionCard(day)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editor) { editor in
                AddSetView(seed: editor.seed, existingSet: editor.existingSet, recentSets: editor.recentSets) { result in
                    if let existing = editor.existingSet {
                        existing.exercise = result.exercise
                        existing.muscleGroup = result.muscleGroup
                        existing.weightKg = result.weightKg
                        existing.reps = result.reps
                    } else {
                        result.loggedOrder = (workout.sets.map(\.loggedOrder).max() ?? -1) + 1
                        workout.sets.append(result)
                    }
                }.presentationDetents([.large])
            }
            .sheet(isPresented: $showingDatePicker) { WorkoutDatePicker(selectedDate: $selectedDate, loggedDates: savedWorkoutDays.map(\.date)).presentationDetents([.large]) }
            .sheet(isPresented: $showingTemplates) {
                TemplatePicker { template in
                    apply(template: template)
                    showingTemplates = false
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingAllSessions) {
                NavigationStack {
                    VStack(spacing: 16) {
                        WorkoutCalendar(selectedDate: Binding(get: { historyCalendarDate }, set: { historyCalendarDate = $0 ?? historyCalendarDate }), loggedDates: savedWorkoutDays.map(\.date)) { date in
                            historyCalendarDate = date
                            if let day = savedWorkoutDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) { openSavedDay(day) }
                        }
                        .padding(.horizontal, 12)
                        Label("A dot marks a day with a saved JourneyFit workout.", systemImage: "circle.fill")
                            .font(.footnote).foregroundStyle(JourneyFitTheme.muted)
                        Spacer()
                    }
                    .navigationTitle("Workout calendar")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAllSessions = false } } }
                }
                .environment(\.calendar, WeekCalendar.mondayFirst)
            }
            .alert("Workout saved", isPresented: $savedMessage) { Button("Done", role: .cancel) {} }
            .onAppear { openRequestedWorkoutIfNeeded() }
            .onChange(of: requestedWorkoutID) { _, _ in openRequestedWorkoutIfNeeded() }
        }
    }

    private func totalReps(for group: DraftExerciseGroup) -> Int {
        workout.sets.filter { group.setIDs.contains($0.id) }.reduce(0) { $0 + $1.reps }
    }

    private func displaySets(for group: DraftExerciseGroup) -> [DisplayedSet] {
        group.setIDs.enumerated().compactMap { index, id in
            workout.sets.first(where: { $0.id == id }).map { DisplayedSet(id: id, displayIndex: index, set: $0) }
        }
    }

    @ViewBuilder
    private func setRow(_ set: LiftSet, displayIndex: Int, setID: UUID) -> some View {
        HStack {
            Text("Set \(displayIndex + 1)").font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(set.weightKg.formatted()) kg × \(set.reps)").font(.subheadline.weight(.semibold))
            Button { editor = SetEditor(seed: nil, existingSet: set, recentSets: recentSets) } label: { Image(systemName: "pencil.circle") }
                .buttonStyle(.borderless).accessibilityLabel("Edit set \(displayIndex + 1)")
            Button(role: .destructive) {
                if let index = workout.sets.firstIndex(where: { $0.id == setID }) { workout.sets.remove(at: index) }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).accessibilityLabel("Delete set \(displayIndex + 1)")
        }
    }

    private var recentSets: [LiftSet] {
        let currentSets = Array(workout.sets.reversed())
        let priorSets = savedWorkouts
            .sorted { $0.loggedAt > $1.loggedAt }
            .flatMap(\.sets)
        return currentSets + priorSets
    }

    private func toggleExercise(_ id: String) {
        if expandedExerciseIDs.contains(id) { expandedExerciseIDs.remove(id) }
        else { expandedExerciseIDs.insert(id) }
    }

    private func moveExercise(_ groupID: String, earlier: Bool) {
        var groups = exerciseGroups
        guard let currentIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let destinationIndex = earlier ? currentIndex - 1 : currentIndex + 1
        guard groups.indices.contains(destinationIndex) else { return }
        groups.swapAt(currentIndex, destinationIndex)

        var order = 0
        for group in groups {
            for setID in group.setIDs {
                guard let set = workout.sets.first(where: { $0.id == setID }) else { continue }
                set.loggedOrder = order
                order += 1
            }
        }
        try? context.save()
    }

    private func closeSavedSession() {
        editor = nil
        workout = StrengthWorkout()
        selectedDate = Calendar.current.startOfDay(for: .now)
        isEditingSavedSession = false
        expandedExerciseIDs.removeAll()
    }

    private func openRequestedWorkoutIfNeeded() {
        guard let requestedWorkoutID,
              let saved = savedWorkouts.first(where: { $0.id == requestedWorkoutID }) else { return }
        workout = saved
        selectedDate = Calendar.current.startOfDay(for: saved.startedAt)
        isEditingSavedSession = true
        expandedExerciseIDs.removeAll()
        self.requestedWorkoutID = nil
    }

    private func apply(template: WorkoutTemplate) {
        workout = StrengthWorkout()
        selectedDate = Calendar.current.startOfDay(for: .now)
        isEditingSavedSession = false
        for item in template.exercises {
            let previous = recentSets.first { $0.muscleGroup == item.muscleGroup && $0.exercise == item.exercise }
            let set = LiftSet(loggedOrder: workout.sets.count, exercise: item.exercise, muscleGroup: item.muscleGroup, weightKg: previous?.weightKg ?? 20, reps: previous?.reps ?? 8)
            workout.sets.append(set)
        }
        expandedExerciseIDs = Set(exerciseGroups.map(\.id))
    }

    private func loadLastWorkout() {
        guard let last = savedWorkouts.sorted(by: { $0.loggedAt > $1.loggedAt }).first else { return }
        workout = StrengthWorkout()
        selectedDate = Calendar.current.startOfDay(for: .now)
        for set in last.sets.sorted(by: { $0.loggedOrder < $1.loggedOrder }) {
            workout.sets.append(LiftSet(loggedOrder: workout.sets.count, exercise: set.exercise, muscleGroup: set.muscleGroup, weightKg: set.weightKg, reps: set.reps))
        }
        expandedExerciseIDs = Set(exerciseGroups.map(\.id))
    }

    private func savedSessionCard(_ day: SavedWorkoutDay) -> some View {
        Button { openSavedDay(day) } label: { JourneyFitCard { savedSessionRow(day) } }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit saved session from \(day.date.formatted(date: .abbreviated, time: .omitted))")
    }

    private func savedSessionRow(_ day: SavedWorkoutDay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline).foregroundStyle(JourneyFitTheme.ink)
                Text("\(day.setCount) set\(day.setCount == 1 ? "" : "s") · \(day.totalReps) reps · \(day.exerciseCount) exercise\(day.exerciseCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(JourneyFitTheme.muted)
            }
            Spacer()
            Image(systemName: "pencil.circle.fill").foregroundStyle(JourneyFitTheme.accent)
        }
    }

    private func openSavedDay(_ day: SavedWorkoutDay) {
        let sessions = day.workouts.sorted {
            if $0.loggedAt != $1.loggedAt { return $0.loggedAt < $1.loggedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let primary = sessions.first else { return }

        // Older versions could create several records on one day. Fold them
        // into the earliest record once, retaining the logged set sequence.
        for duplicate in sessions.dropFirst() {
            let transferredSets = duplicate.sets
            primary.sets.append(contentsOf: transferredSets)
            duplicate.sets.removeAll()
            context.delete(duplicate)
        }
        if sessions.count > 1 { try? context.save() }

        workout = primary
        selectedDate = Calendar.current.startOfDay(for: primary.startedAt)
        isEditingSavedSession = true
        expandedExerciseIDs.removeAll()
        showingAllSessions = false
    }
}

struct ExerciseSeed {
    let muscleGroup: String
    let exercise: String
    let weightKg: Double?
    let reps: Int?
}

struct SetEditor: Identifiable {
    let id = UUID()
    let seed: ExerciseSeed?
    let existingSet: LiftSet?
    let recentSets: [LiftSet]
}

struct DraftExerciseGroup: Identifiable {
    let id: String
    let muscleGroup: String
    let exercise: String
    let setIDs: [UUID]
}

struct DisplayedSet: Identifiable {
    let id: UUID
    let displayIndex: Int
    let set: LiftSet
}

struct SavedWorkoutDay: Identifiable {
    let date: Date
    let workouts: [StrengthWorkout]
    var id: Date { date }
    var sets: [LiftSet] { workouts.flatMap(\.sets) }
    var setCount: Int { sets.count }
    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var exerciseCount: Int { Set(sets.map(\.exercise)).count }
}

struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let choose: (WorkoutTemplate) -> Void
    @AppStorage("journeyFit.customTemplates") private var legacyTemplatesData = Data()
    @AppStorage("journeyFit.templates") private var savedTemplatesData = Data()
    @AppStorage("journeyFit.templatesMigrated") private var templatesMigrated = false
    @State private var editor: TemplateEditorState?

    private var templates: [WorkoutTemplate] {
        (try? JSONDecoder().decode([WorkoutTemplate].self, from: savedTemplatesData)) ?? WorkoutTemplate.betaTemplates
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(templates) { template in templateRow(template) }
                    .onDelete { offsets in
                        var updated = templates
                        updated.remove(atOffsets: offsets)
                        save(updated)
                    }
            }
            .navigationTitle("Workout template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = TemplateEditorState(template: WorkoutTemplate(name: "My workout", subtitle: "", exercises: []), isNew: true) } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editor) { state in
                TemplateEditor(template: state.template, isNew: state.isNew) { updated in
                    var updatedTemplates = templates
                    if let index = updatedTemplates.firstIndex(where: { $0.id == updated.id }) { updatedTemplates[index] = updated }
                    else { updatedTemplates.append(updated) }
                    save(updatedTemplates)
                }
            }
            .onAppear { migrateTemplatesIfNeeded() }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                choose(template)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline)
                    if !template.subtitle.isEmpty { Text(template.subtitle).font(.subheadline).foregroundStyle(.secondary) }
                    Text(template.exercises.map(\.exercise).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.padding(.vertical, 4)
            }.buttonStyle(.plain)
            Button("Edit") {
                editor = TemplateEditorState(template: template, isNew: false)
            }
            .font(.caption.weight(.semibold)).buttonStyle(.borderless).foregroundStyle(JourneyFitTheme.accent)
        }
    }

    private func save(_ templates: [WorkoutTemplate]) {
        savedTemplatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }

    private func migrateTemplatesIfNeeded() {
        guard !templatesMigrated else { return }
        let legacy = (try? JSONDecoder().decode([WorkoutTemplate].self, from: legacyTemplatesData)) ?? []
        save(WorkoutTemplate.betaTemplates + legacy)
        templatesMigrated = true
    }
}

struct TemplateEditorState: Identifiable {
    let id = UUID()
    let template: WorkoutTemplate
    let isNew: Bool
}

struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutTemplate
    let isNew: Bool
    let save: (WorkoutTemplate) -> Void

    init(template: WorkoutTemplate, isNew: Bool, save: @escaping (WorkoutTemplate) -> Void) {
        _draft = State(initialValue: template)
        self.isNew = isNew
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("TEMPLATE") {
                    TextField("Name", text: $draft.name)
                    TextField("Description (optional)", text: $draft.subtitle)
                }
                Section("EXERCISES") {
                    ForEach($draft.exercises) { $item in
                        VStack(alignment: .leading) {
                            Picker("Muscle group", selection: $item.muscleGroup) {
                                ForEach(ExerciseCatalog.muscleGroups, id: \.self) { Text($0).tag($0) }
                            }
                            .onChange(of: item.muscleGroup) { _, group in item.exercise = ExerciseCatalog.exercises(for: group).first ?? "" }
                            Picker("Exercise", selection: $item.exercise) {
                                ForEach(ExerciseCatalog.exercises(for: item.muscleGroup), id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }
                    Button { draft.exercises.append(TemplateExercise(muscleGroup: ExerciseCatalog.muscleGroups.first ?? "Chest", exercise: ExerciseCatalog.exercises(for: ExerciseCatalog.muscleGroups.first ?? "Chest").first ?? "")) } label: { Label("Add exercise", systemImage: "plus") }
                }
            }
            .navigationTitle(isNew ? "New template" : "Edit template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); guard !draft.name.isEmpty, !draft.exercises.isEmpty else { return }; save(draft); dismiss() } }
            }
        }
    }
}

struct AddSetView: View {
    @Environment(\.dismiss) private var dismiss
    let add: (LiftSet) -> Void
    let existingSet: LiftSet?
    let recentSets: [LiftSet]
    @State private var muscle: String
    @State private var exercise: String
    @State private var weightKg: Double
    @State private var reps: Int
    @State private var unit: WeightUnit = .kg

    init(seed: ExerciseSeed?, existingSet: LiftSet?, recentSets: [LiftSet], add: @escaping (LiftSet) -> Void) {
        self.add = add
        self.existingSet = existingSet
        self.recentSets = recentSets
        let defaultMuscle = ExerciseCatalog.muscleGroups[0]
        let muscle = existingSet?.muscleGroup ?? seed?.muscleGroup ?? defaultMuscle
        let exercise = existingSet?.exercise ?? seed?.exercise ?? ExerciseCatalog.exercises(for: muscle)[0]
        let previousSet = recentSets.first { $0.muscleGroup == muscle && $0.exercise == exercise }
        self._muscle = State(initialValue: muscle)
        self._exercise = State(initialValue: exercise)
        self._weightKg = State(initialValue: existingSet?.weightKg ?? seed?.weightKg ?? previousSet?.weightKg ?? 20)
        self._reps = State(initialValue: existingSet?.reps ?? seed?.reps ?? previousSet?.reps ?? 8)
    }

    private var displayedWeight: Binding<Double> {
        Binding(
            get: { unit.displayValue(fromKilograms: weightKg) },
            set: { weightKg = max(0, unit.kilograms(fromDisplayValue: $0)) }
        )
    }

    var body: some View {
        NavigationStack { Form {
            Picker("Muscle group", selection: $muscle) { ForEach(ExerciseCatalog.muscleGroups, id: \.self) { Text($0).tag($0) } }
                .onChange(of: muscle) { _, newValue in
                    exercise = ExerciseCatalog.exercises(for: newValue)[0]
                    applyPreviousSetDefault()
                }
            Picker("Exercise", selection: $exercise) { ForEach(ExerciseCatalog.exercises(for: muscle), id: \.self) { Text($0).tag($0) } }
                .onChange(of: exercise) { _, _ in applyPreviousSetDefault() }
            Section("Weight") {
                Picker("Unit", selection: $unit) { ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                HStack {
                    Button { weightKg = max(0, weightKg - unit.kilograms(fromDisplayValue: unit.step)) } label: { Image(systemName: "minus.circle.fill").font(.title2) }.buttonStyle(.borderless).frame(width: 44, height: 44)
                    TextField("Weight", value: displayedWeight, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                    Text(unit.rawValue).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                    Button { weightKg += unit.kilograms(fromDisplayValue: unit.step) } label: { Image(systemName: "plus.circle.fill").font(.title2) }.buttonStyle(.borderless).frame(width: 44, height: 44)
                }
            }
            Section("Reps") {
                HStack {
                    Button { reps = max(1, reps - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }.buttonStyle(.borderless).frame(width: 44, height: 44)
                    TextField("Reps", value: $reps, format: .number).keyboardType(.numberPad).multilineTextAlignment(.center)
                    Button { reps = min(100, reps + 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }.buttonStyle(.borderless).frame(width: 44, height: 44)
                }
            }
        }.navigationTitle(existingSet == nil ? "Add set" : "Edit set").toolbar {
            ToolbarItem(placement: .confirmationAction) { Button(existingSet == nil ? "Add" : "Save") { add(LiftSet(exercise: exercise, muscleGroup: muscle, weightKg: weightKg, reps: reps)); dismiss() } }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        } }
    }

    private func applyPreviousSetDefault() {
        guard existingSet == nil,
              let previousSet = recentSets.first(where: { $0.muscleGroup == muscle && $0.exercise == exercise }) else { return }
        weightKg = previousSet.weightKg
        reps = previousSet.reps
    }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var step: Double { self == .kg ? 0.5 : 1 }
    func displayValue(fromKilograms value: Double) -> Double { self == .kg ? value : value * 2.20462262 }
    func kilograms(fromDisplayValue value: Double) -> Double { self == .kg ? value : value / 2.20462262 }
}

struct WorkoutDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date?
    let loggedDates: [Date]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                WorkoutCalendar(selectedDate: $selectedDate, loggedDates: loggedDates) { date in
                    selectedDate = date
                    dismiss()
                }
                Label("A dot marks a day with a saved JourneyFit workout.", systemImage: "circle.fill")
                    .font(.footnote).foregroundStyle(JourneyFitTheme.muted)
                Spacer()
            }
            .padding(.top, 8).navigationTitle("Workout date")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .environment(\.calendar, WeekCalendar.mondayFirst)
    }
}

struct WorkoutCalendar: UIViewRepresentable {
    @Binding var selectedDate: Date?
    let loggedDates: [Date]
    let onSelect: (Date) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = WeekCalendar.mondayFirst
        calendarView.locale = .current
        calendarView.fontDesign = .rounded
        calendarView.delegate = context.coordinator
        calendarView.availableDateRange = DateInterval(start: Date(timeIntervalSince1970: 0), end: .now)
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        if let selectedDate { selection.selectedDate = WeekCalendar.mondayFirst.dateComponents([.calendar, .year, .month, .day], from: selectedDate) }
        calendarView.selectionBehavior = selection
        context.coordinator.calendarView = calendarView
        let loggedComponents = loggedDates.map { WeekCalendar.mondayFirst.dateComponents([.calendar, .year, .month, .day], from: $0) }
        calendarView.reloadDecorations(forDateComponents: loggedComponents, animated: false)
        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let components = loggedDates.map { WeekCalendar.mondayFirst.dateComponents([.calendar, .year, .month, .day], from: $0) }
        uiView.reloadDecorations(forDateComponents: components, animated: true)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: WorkoutCalendar
        weak var calendarView: UICalendarView?

        init(parent: WorkoutCalendar) { self.parent = parent }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = WeekCalendar.mondayFirst.date(from: dateComponents),
                  parent.loggedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) else { return nil }
            return .default(color: .systemBlue, size: .large)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = WeekCalendar.mondayFirst.date(from: dateComponents) else { return }
            parent.selectedDate = Calendar.current.startOfDay(for: date)
            parent.onSelect(Calendar.current.startOfDay(for: date))
        }
    }
}

enum ReportDateTarget: String, Identifiable {
    case start, end
    var id: String { rawValue }
}

struct ReportDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selectedDate: Date
    let allowedRange: ClosedRange<Date>
    @State private var chosenDate: Date

    init(title: String, selectedDate: Binding<Date>, allowedRange: ClosedRange<Date>) {
        self.title = title
        self._selectedDate = selectedDate
        self.allowedRange = allowedRange
        self._chosenDate = State(initialValue: selectedDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $chosenDate, in: allowedRange, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: chosenDate) { _, newValue in
                    selectedDate = Calendar.current.startOfDay(for: newValue)
                    dismiss()
                }
        }
        .environment(\.calendar, WeekCalendar.mondayFirst)
    }
}

// MARK: - InBody and PDF reports

struct ReportsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InBodyReport.createdAt, order: .reverse) private var inBodyReports: [InBodyReport]
    @Query(sort: \GeneratedReport.createdAt, order: .reverse) private var generatedReports: [GeneratedReport]
    @Query(sort: \StrengthWorkout.startedAt, order: .reverse) private var workouts: [StrengthWorkout]
    @EnvironmentObject private var health: HealthKitManager
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var exportURL: URL?
    @State private var toastMessage: String?
    @State private var selectedInBodyIDs = Set<UUID>()
    @State private var selectedInBodyName: String?
    @State private var showingPreview = false
    @State private var datePickerTarget: ReportDateTarget?
    @State private var reportToDelete: GeneratedReport?
    @State private var startDate = HealthKitManager.mondayThroughSunday().start
    @State private var endDate = HealthKitManager.mondayThroughSunday().end.addingTimeInterval(-1)

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyFitTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("REPORTS").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(JourneyFitTheme.accent)
                        Text("Review the work.\nShare the story.").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(JourneyFitTheme.ink)
                        JourneyFitCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("REPORT PERIOD", systemImage: "calendar.badge.clock").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(JourneyFitTheme.muted)
                                Button { datePickerTarget = .start } label: {
                                    HStack { Text("From"); Spacer(); Text(startDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(JourneyFitTheme.accent); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(JourneyFitTheme.muted) }
                                }.buttonStyle(.plain)
                                Divider()
                                Button { datePickerTarget = .end } label: {
                                    HStack { Text("To"); Spacer(); Text(endDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(JourneyFitTheme.accent); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(JourneyFitTheme.muted) }
                                }.buttonStyle(.plain)
                            }
                        }
                        JourneyFitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("INBODY REPORT", systemImage: "doc.viewfinder").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(JourneyFitTheme.muted)
                                Text("Add an InBody image when you want to append it unchanged to this PDF. Import reports for InBody Progress from the Progress tab.").font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Add InBody report", systemImage: "photo.badge.plus") }.buttonStyle(.bordered).tint(JourneyFitTheme.accent)
                                if let attachedName = selectedInBodyName {
                                    HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(JourneyFitTheme.success); Text("Attached: \(attachedName)").font(.subheadline); Spacer(); Button { selectedInBodyIDs.removeAll(); selectedInBodyName = nil } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove InBody attachment") }
                                }
                            }
                        }
                        Button { Task { await generate() } } label: { Label("Create PDF report", systemImage: "arrow.down.doc.fill").frame(maxWidth: .infinity).font(.headline).padding(.vertical, 6) }.buttonStyle(.borderedProminent).tint(JourneyFitTheme.accent)
                        if let exportURL { ShareLink(item: exportURL) { Label("Share or save PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(JourneyFitTheme.accent) }
                        if !generatedReports.isEmpty {
                            JourneyFitCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("SAVED REPORTS", systemImage: "archivebox.fill").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(JourneyFitTheme.muted)
                                    ForEach(generatedReports) { report in
                                        HStack { Image(systemName: "doc.richtext").foregroundStyle(JourneyFitTheme.accent); Text(report.displayName).font(.subheadline).lineLimit(1); Spacer(); Button { exportURL = ReportStorage.url(named: report.localFilename); showingPreview = true } label: { Image(systemName: "eye") }; ShareLink(item: ReportStorage.url(named: report.localFilename)) { Image(systemName: "square.and.arrow.up") }; Button(role: .destructive) { reportToDelete = report } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(report.displayName)") }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedPhoto) { _, item in Task { await importImage(item) } }
            .onDisappear { selectedPhoto = nil; selectedInBodyIDs.removeAll(); selectedInBodyName = nil }
            .sheet(item: $datePickerTarget) { target in
                Group {
                    if target == .start {
                        ReportDatePicker(title: "Report start date", selectedDate: $startDate, allowedRange: Date(timeIntervalSince1970: 0)...endDate)
                    } else {
                        ReportDatePicker(title: "Report end date", selectedDate: $endDate, allowedRange: startDate...Calendar.current.startOfDay(for: .now))
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingPreview) { if let exportURL { PDFPreviewScreen(url: exportURL) } }
            .alert("Delete saved report?", isPresented: Binding(get: { reportToDelete != nil }, set: { if !$0 { reportToDelete = nil } }), presenting: reportToDelete) { report in
                Button("Delete", role: .destructive) { deleteSavedReport(report) }
                Button("Cancel", role: .cancel) { reportToDelete = nil }
            } message: { report in Text("\(report.displayName) will be permanently removed from this iPhone.") }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage).font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12).background(.black.opacity(0.82), in: Capsule()).padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .environment(\.calendar, WeekCalendar.mondayFirst)
    }

    private func importImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            let url = try InBodyStorage.save(data: data)
            let report = InBodyReport(localFilename: url.lastPathComponent, displayName: "InBody report · \(Date.now.formatted(date: .abbreviated, time: .omitted))")
            context.insert(report)
            selectedInBodyIDs = [report.id]
            selectedInBodyName = report.displayName
            try context.save()
            showToast("InBody image added unchanged.")
        } catch { showToast("Could not save the InBody image.") }
        selectedPhoto = nil
    }

    private func generate() async {
        guard startDate <= endDate else { showToast("Choose a start date on or before the end date."); return }
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        let range = DateInterval(start: rangeStart, end: rangeEnd)
        // Compare calendar days rather than timestamps: a report ending on Aug 2
        // includes Aug 2 and categorically excludes Aug 3.
        let selected = workouts.filter {
            let workoutDay = calendar.startOfDay(for: $0.startedAt)
            return workoutDay >= rangeStart && workoutDay < rangeEnd
        }
        do {
            async let dailySteps = health.readDailySteps(in: range)
            async let healthWorkouts = health.readWorkouts(in: range)
            let records = try await healthWorkouts
            let includedInBody = inBodyReports.filter { selectedInBodyIDs.contains($0.id) }
            let url = try ReportGenerator.makePDF(range: range, workouts: selected, dailySteps: try await dailySteps, healthWorkouts: records, inBodyReports: includedInBody)
            exportURL = url
            context.insert(GeneratedReport(localFilename: url.lastPathComponent, displayName: url.deletingPathExtension().lastPathComponent))
            try context.save()
            selectedInBodyIDs.removeAll()
            selectedInBodyName = nil
            showToast("PDF saved. Review it before sharing.")
            showingPreview = true
        } catch { showToast("Could not generate the PDF.") }
    }

    private func deleteSavedReport(_ report: GeneratedReport) {
        if exportURL?.lastPathComponent == report.localFilename { exportURL = nil }
        try? FileManager.default.removeItem(at: ReportStorage.url(named: report.localFilename))
        context.delete(report)
        do { try context.save(); showToast("Saved report deleted.") }
        catch { showToast("Could not delete the saved report.") }
        reportToDelete = nil
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastMessage == text { toastMessage = nil }
        }
    }
}

enum InBodyStorage {
    static func folder() throws -> URL { let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "inbody-reports"); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    static func save(data: Data) throws -> URL { let url = try folder().appending(path: "\(UUID().uuidString).jpg"); try data.write(to: url, options: .atomic); return url }
    static func image(named filename: String) -> UIImage? { try? UIImage(data: Data(contentsOf: try folder().appending(path: filename))) }
}

enum InBodyReportReader {
    static func read(_ data: Data) async -> InBodyDetectedValues? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: parse(lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            }
        }
    }

    private static func parse(_ lines: [String]) -> InBodyDetectedValues {
        let text = lines.joined(separator: " ")
        return InBodyDetectedValues(
            weightKg: firstNumber(in: text, labels: ["Weight"]),
            bodyFatPercent: firstNumber(in: text, labels: ["Percent Body Fat", "Body Fat %", "PBF"]),
            visceralFatLevel: firstNumber(in: text, labels: ["Visceral Fat Level", "Visceral Fat", "VFL"]),
            bmi: firstNumber(in: text, labels: ["BMI"])
        )
    }

    private static func firstNumber(in text: String, labels: [String]) -> Double? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label).replacingOccurrences(of: "\\ ", with: "\\s+")
            let pattern = "(?i)\\b\(escaped)\\b[^0-9]{0,18}([0-9]{1,3}(?:\\.[0-9]{1,2})?)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return Double(text[range])
        }
        return nil
    }
}

enum ReportStorage {
    static func folder() throws -> URL { let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "generated-reports"); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    static func url(named filename: String) -> URL { (try? folder().appending(path: filename)) ?? FileManager.default.temporaryDirectory.appending(path: filename) }
    static func newURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return try folder().appending(path: "JourneyFit-\(formatter.string(from: .now)).pdf")
    }
    static func save(data: Data) throws -> URL { let url = try newURL(); try data.write(to: url, options: .atomic); return url }
}

struct JourneyFitBackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let workouts: [BackupWorkout]
    let inBodyReports: [BackupAttachment]
    let inBodyMeasurements: [BackupInBodyMeasurement]?
    let generatedReports: [BackupAttachment]
}

struct BackupInBodyMeasurement: Codable {
    let id: UUID
    let measuredAt: Date
    let weightKg: Double
    let bodyFatPercent: Double
    let visceralFatLevel: Double
    let bmi: Double
}

struct BackupWorkout: Codable {
    let id: UUID
    let startedAt: Date
    let loggedAt: Date?
    let note: String
    let sets: [BackupSet]
}

struct BackupSet: Codable {
    let id: UUID
    let loggedOrder: Int?
    let exercise: String
    let muscleGroup: String
    let weightKg: Double
    let reps: Int
    let rpe: Double?
    let isWarmup: Bool
    let takenToFailure: Bool
}

struct BackupAttachment: Codable {
    let id: UUID
    let createdAt: Date
    let displayName: String
    let data: Data
}

enum JourneyFitBackup {
    static func export(workouts: [StrengthWorkout], inBodyReports: [InBodyReport], inBodyMeasurements: [InBodyMeasurement], generatedReports: [GeneratedReport]) throws -> URL {
        let backup = JourneyFitBackupFile(
            version: 2,
            exportedAt: .now,
            workouts: workouts.map { workout in BackupWorkout(id: workout.id, startedAt: workout.startedAt, loggedAt: workout.loggedAt, note: workout.note, sets: workout.sets.map { set in BackupSet(id: set.id, loggedOrder: set.loggedOrder, exercise: set.exercise, muscleGroup: set.muscleGroup, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup, takenToFailure: set.takenToFailure) }) },
            inBodyReports: inBodyReports.compactMap { report in guard let data = try? Data(contentsOf: try InBodyStorage.folder().appending(path: report.localFilename)) else { return nil }; return BackupAttachment(id: report.id, createdAt: report.createdAt, displayName: report.displayName, data: data) },
            inBodyMeasurements: inBodyMeasurements.map { BackupInBodyMeasurement(id: $0.id, measuredAt: $0.measuredAt, weightKg: $0.weightKg, bodyFatPercent: $0.bodyFatPercent, visceralFatLevel: $0.visceralFatLevel, bmi: $0.bmi) },
            generatedReports: generatedReports.compactMap { report in guard let data = try? Data(contentsOf: ReportStorage.url(named: report.localFilename)) else { return nil }; return BackupAttachment(id: report.id, createdAt: report.createdAt, displayName: report.displayName, data: data) }
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let output = FileManager.default.temporaryDirectory.appending(path: "JourneyFit-backup-\(Int(Date.now.timeIntervalSince1970)).json")
        try encoder.encode(backup).write(to: output, options: .atomic)
        return output
    }

    static func read(from url: URL) throws -> JourneyFitBackupFile {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(JourneyFitBackupFile.self, from: Data(contentsOf: url))
    }
}

enum ReportGenerator {
    static func makePDF(range: DateInterval, workouts: [StrengthWorkout], dailySteps: [(date: Date, steps: Int)], healthWorkouts: [HKWorkout], inBodyReports: [InBodyReport]) throws -> URL {
        let output = try ReportStorage.newURL()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: output) { pdf in
            let margin: CGFloat = 36; let width: CGFloat = 540; let pageBottom: CGFloat = 750
            let headerInk = UIColor(red: 0.10, green: 0.14, blue: 0.17, alpha: 1)
            let accent = UIColor(red: 0.18, green: 0.40, blue: 0.34, alpha: 1)
            let ink = UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
            let mutedInk = UIColor(red: 0.31, green: 0.33, blue: 0.35, alpha: 1)
            func draw(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
                let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byWordWrapping
                (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style], context: nil)
            }
            func roundedCard(_ rect: CGRect, color: UIColor = UIColor(white: 0.96, alpha: 1)) { color.setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 15).fill() }
            func startPage(_ title: String) -> CGFloat {
                pdf.beginPage()
                headerInk.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 612, height: 108))
                draw("JourneyFit", in: CGRect(x: margin, y: 28, width: width, height: 34), font: .boldSystemFont(ofSize: 27), color: .white)
                draw(title, in: CGRect(x: margin, y: 66, width: width, height: 22), font: .systemFont(ofSize: 13, weight: .medium), color: UIColor(white: 0.92, alpha: 1))
                return 134
            }
            func section(_ title: String, _ y: inout CGFloat) { draw(title.uppercased(), in: CGRect(x: margin, y: y, width: width, height: 20), font: .systemFont(ofSize: 11, weight: .bold), color: accent); y += 27 }
            func table(headers: [String], rows: [[String]], widths: [CGFloat], pageTitle: String, y: inout CGFloat) {
                func header() { accent.setFill(); UIRectFill(CGRect(x: margin, y: y, width: width, height: 26)); var x = margin; for index in headers.indices { draw(headers[index], in: CGRect(x: x + 5, y: y + 7, width: widths[index] - 10, height: 14), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white); x += widths[index] }; y += 26 }
                header()
                for (index, row) in rows.enumerated() {
                    let height: CGFloat = 40
                    if y + height > pageBottom { y = startPage(pageTitle); section("Continued", &y); header() }
                    if index.isMultiple(of: 2) { UIColor(white: 0.96, alpha: 1).setFill(); UIRectFill(CGRect(x: margin, y: y, width: width, height: height)) }
                    var x = margin
                    for column in row.indices { draw(row[column], in: CGRect(x: x + 5, y: y + 7, width: widths[column] - 10, height: height - 10), font: .systemFont(ofSize: 9.5, weight: column == 1 ? .semibold : .regular), color: ink); x += widths[column] }
                    y += height
                }
            }

            let totalSteps = dailySteps.reduce(0) { $0 + $1.steps }
            let averageSteps = dailySteps.isEmpty ? 0 : totalSteps / dailySteps.count
            var y = startPage("Progress report · \(range.start.formatted(date: .abbreviated, time: .omitted)) – \(range.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
            section("At a glance", &y)
            let summaryRect = CGRect(x: margin, y: y, width: width, height: 92); roundedCard(summaryRect)
            let metrics = [("\(totalSteps.formatted())", "TOTAL STEPS"), ("\(averageSteps.formatted())", "AVG STEPS / DAY"), ("\(healthWorkouts.count)", "FITNESS WORKOUTS")]
            for index in metrics.indices { let cellWidth = width / 3; let x = margin + CGFloat(index) * cellWidth; draw(metrics[index].0, in: CGRect(x: x + 16, y: y + 22, width: cellWidth - 30, height: 28), font: .boldSystemFont(ofSize: 20), color: ink, alignment: .center); draw(metrics[index].1, in: CGRect(x: x + 10, y: y + 57, width: cellWidth - 20, height: 18), font: .systemFont(ofSize: 8.5, weight: .bold), color: mutedInk, alignment: .center) }
            y += 118
            section("Daily steps", &y)
            let stepRows = dailySteps.map { [$0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), $0.steps.formatted()] }
            if stepRows.isEmpty { draw("No step data was available for this period.", in: CGRect(x: margin, y: y, width: width, height: 20), font: .systemFont(ofSize: 12), color: mutedInk) } else { table(headers: ["DAY", "STEPS"], rows: stepRows, widths: [330, 210], pageTitle: "Daily steps", y: &y) }

            y = startPage("Apple Fitness workout history")
            section("Workouts", &y)
            let workoutRows = healthWorkouts.sorted { $0.startDate < $1.startDate }.map { workout -> [String] in
                let active = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
                let basal = workout.statistics(for: basalType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                let distance = workout.totalDistance.map { "\($0.doubleValue(for: .meterUnit(with: .kilo)).formatted(.number.precision(.fractionLength(1)))) km" } ?? "—"
                return [workout.startDate.formatted(.dateTime.day().month(.abbreviated).hour().minute()), workoutName(workout), "\(Int(workout.duration / 60)) min", distance, active.map { "\(Int($0)) kcal" } ?? "—", active.map { "\(Int($0 + basal)) kcal" } ?? "—"]
            }
            if workoutRows.isEmpty { draw("No Apple Fitness workouts were recorded in this period.", in: CGRect(x: margin, y: y, width: width, height: 20), font: .systemFont(ofSize: 12), color: mutedInk) } else { table(headers: ["WHEN", "TYPE", "DURATION", "DISTANCE", "ACTIVE", "TOTAL"], rows: workoutRows, widths: [110, 130, 70, 75, 75, 80], pageTitle: "Apple Fitness workout history", y: &y) }

            let calendar = Calendar.current
            let reportWorkouts = workouts.filter {
                let workoutDay = calendar.startOfDay(for: $0.startedAt)
                return workoutDay >= calendar.startOfDay(for: range.start) && workoutDay < range.end
            }

            y = startPage("JourneyFit strength logs")
            section("Logged sessions", &y)
            if reportWorkouts.isEmpty { draw("No JourneyFit workout logs were recorded in this period.", in: CGRect(x: margin, y: y, width: width, height: 20), font: .systemFont(ofSize: 12), color: mutedInk) }
            let orderedWorkouts = reportWorkouts.sorted {
                let leftDay = calendar.startOfDay(for: $0.startedAt)
                let rightDay = calendar.startOfDay(for: $1.startedAt)
                if leftDay != rightDay { return leftDay < rightDay }
                if $0.loggedAt != $1.loggedAt { return $0.loggedAt < $1.loggedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            var orderedDays: [Date] = []
            var workoutsByDay: [Date: [StrengthWorkout]] = [:]
            for workout in orderedWorkouts {
                let day = calendar.startOfDay(for: workout.startedAt)
                if workoutsByDay[day] == nil { orderedDays.append(day) }
                workoutsByDay[day, default: []].append(workout)
            }
            for day in orderedDays {
                guard let sessions = workoutsByDay[day] else { continue }
                let daySets = sessions.flatMap { $0.sets.sorted { $0.loggedOrder < $1.loggedOrder } }
                // One row per exercise, ordered by the first set logged for it.
                // This keeps a complete exercise together even if the user
                // alternated between exercises while recording the workout.
                var exerciseRows: [(muscleGroup: String, exercise: String, sets: [LiftSet])] = []
                for set in daySets {
                    if let existingIndex = exerciseRows.firstIndex(where: { $0.muscleGroup == set.muscleGroup && $0.exercise == set.exercise }) {
                        exerciseRows[existingIndex].sets.append(set)
                    } else {
                        exerciseRows.append((set.muscleGroup, set.exercise, [set]))
                    }
                }
                let notes = sessions.map(\.note).filter { !$0.isEmpty }
                if y + 48 > pageBottom { y = startPage("JourneyFit strength logs"); section("Logged sessions", &y) }
                draw(day.formatted(date: .complete, time: .omitted), in: CGRect(x: margin, y: y, width: width, height: 20), font: .boldSystemFont(ofSize: 14), color: ink)
                draw("\(exerciseRows.count) exercise\(exerciseRows.count == 1 ? "" : "s") · \(daySets.count) sets · \(daySets.reduce(0) { $0 + $1.reps }) total reps", in: CGRect(x: margin, y: y + 19, width: width, height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: accent)
                y += 42
                let rows = exerciseRows.map { row -> [String] in
                    let uniqueWeights = Array(Set(row.sets.map(\.weightKg)))
                    let weight = uniqueWeights.count == 1 ? "\(uniqueWeights[0].formatted()) kg" : "Mixed"
                    var setColumns = Array(repeating: "-", count: 4)
                    for (index, set) in row.sets.prefix(4).enumerated() {
                        setColumns[index] = uniqueWeights.count == 1 ? String(set.reps) : "\(set.weightKg.formatted()) × \(set.reps)"
                    }
                    if row.sets.count > 4 {
                        setColumns[3] += " +\(row.sets.count - 4)"
                    }
                    return [row.muscleGroup, row.exercise, weight] + setColumns
                }
                table(headers: ["MUSCLE GROUP", "EXERCISE", "WEIGHT", "SET 1", "SET 2", "SET 3", "SET 4"], rows: rows, widths: [80, 130, 70, 65, 65, 65, 65], pageTitle: "JourneyFit strength logs", y: &y)
                for note in notes {
                    if y + 20 > pageBottom { y = startPage("JourneyFit strength logs"); section("Logged sessions", &y) }
                    draw("Note: \(note)", in: CGRect(x: margin, y: y + 3, width: width, height: 19), font: .italicSystemFont(ofSize: 10), color: mutedInk)
                    y += 20
                }
                y += 14
            }

            for report in inBodyReports { guard let image = InBodyStorage.image(named: report.localFilename) else { continue }; y = startPage("InBody report · \(report.displayName)"); let ratio = min(width / image.size.width, (792 - y - 42) / image.size.height); image.draw(in: CGRect(x: margin, y: y, width: image.size.width * ratio, height: image.size.height * ratio)) }
        }
        return output
    }

    private static func workoutName(_ workout: HKWorkout) -> String {
        switch workout.workoutActivityType {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        default: return "Workout"
        }
    }
}

struct PDFPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var body: some View {
        NavigationStack {
            PDFPreview(url: url).ignoresSafeArea(edges: .bottom)
                .navigationTitle("Report preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } } }
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; return view }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(url: url) }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StrengthWorkout.startedAt, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \InBodyReport.createdAt, order: .reverse) private var inBodyReports: [InBodyReport]
    @Query(sort: \InBodyMeasurement.measuredAt, order: .reverse) private var inBodyMeasurements: [InBodyMeasurement]
    @Query(sort: \GeneratedReport.createdAt, order: .reverse) private var generatedReports: [GeneratedReport]
    @State private var backupURL: URL?
    @State private var showingImporter = false
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                JourneyFitTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("PROFILE").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(JourneyFitTheme.accent)
                        Text("Private by\ndesign.").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(JourneyFitTheme.ink)
                        JourneyFitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Backup & Restore", systemImage: "externaldrive.badge.checkmark").font(.headline)
                                Text("Back up all workouts, set logs, InBody measurements and images, and saved PDF reports as one portable JourneyFit backup file.").font(.subheadline).foregroundStyle(JourneyFitTheme.muted)
                                Button { createBackup() } label: { Label("Create complete backup", systemImage: "arrow.down.doc") }.buttonStyle(.borderedProminent).tint(JourneyFitTheme.accent)
                                if let backupURL { ShareLink(item: backupURL) { Label("Save or share backup", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) }
                                Button { showingImporter = true } label: { Label("Restore from backup", systemImage: "arrow.up.doc") }.buttonStyle(.bordered)
                                if let backupMessage { Text(backupMessage).font(.footnote).foregroundStyle(JourneyFitTheme.muted) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            restoreBackup(from: url)
        }
    }

    private func createBackup() {
        do {
            backupURL = try JourneyFitBackup.export(workouts: workouts, inBodyReports: inBodyReports, inBodyMeasurements: inBodyMeasurements, generatedReports: generatedReports)
            backupMessage = "Backup ready. Save it in Files or iCloud Drive so it survives an app deletion."
        } catch {
            backupMessage = "Could not create the backup."
        }
    }

    private func restoreBackup(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try JourneyFitBackup.read(from: url)
            guard backup.version == 1 || backup.version == 2 else { backupMessage = "This backup version is not supported."; return }
            let workoutIDs = Set(workouts.map(\.id))
            let inBodyIDs = Set(inBodyReports.map(\.id))
            let measurementIDs = Set(inBodyMeasurements.map(\.id))
            let reportIDs = Set(generatedReports.map(\.id))
            var restoredWorkouts = 0
            var restoredFiles = 0
            for record in backup.workouts where !workoutIDs.contains(record.id) {
                let workout = StrengthWorkout(id: record.id, startedAt: record.startedAt, loggedAt: record.loggedAt ?? record.startedAt, note: record.note)
                workout.sets = record.sets.enumerated().map { index, set in
                    LiftSet(id: set.id, loggedOrder: set.loggedOrder ?? index, exercise: set.exercise, muscleGroup: set.muscleGroup, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup, takenToFailure: set.takenToFailure)
                }
                context.insert(workout)
                restoredWorkouts += 1
            }
            for attachment in backup.inBodyReports where !inBodyIDs.contains(attachment.id) {
                let file = try InBodyStorage.save(data: attachment.data)
                context.insert(InBodyReport(id: attachment.id, createdAt: attachment.createdAt, localFilename: file.lastPathComponent, displayName: attachment.displayName))
                restoredFiles += 1
            }
            for measurement in backup.inBodyMeasurements ?? [] where !measurementIDs.contains(measurement.id) {
                context.insert(InBodyMeasurement(id: measurement.id, measuredAt: measurement.measuredAt, weightKg: measurement.weightKg, bodyFatPercent: measurement.bodyFatPercent, visceralFatLevel: measurement.visceralFatLevel, bmi: measurement.bmi))
            }
            for attachment in backup.generatedReports where !reportIDs.contains(attachment.id) {
                let file = try ReportStorage.save(data: attachment.data)
                context.insert(GeneratedReport(id: attachment.id, createdAt: attachment.createdAt, localFilename: file.lastPathComponent, displayName: attachment.displayName))
                restoredFiles += 1
            }
            try context.save()
            backupMessage = "Restore complete: \(restoredWorkouts) workout(s) and \(restoredFiles) saved file(s) added."
        } catch {
            backupMessage = "Could not restore that backup."
        }
    }
}
