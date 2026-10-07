#if os(iOS)
import SwiftUI
import WhoopStore

/// Delt Lab "Train" screen: daily workout adjusted by NOOP's own Charge (recovery) score, a weight log
/// that suggests next loads, and a water tracker. Everything is stored on-device in UserDefaults.
struct TrainView: View {
    @EnvironmentObject private var repo: Repository

    private struct Ex { let name: String; let sets: Int; let reps: String; let tip: String }
    private struct Logged: Codable { var w: Double; var r: Int }

    private static let plan: [String: (title: String, ex: [Ex])] = [
        "Mon": ("Shoulders: strength", [
            Ex(name: "Seated dumbbell overhead press", sets: 4, reps: "6-8", tip: "Heaviest lift. Stop 1-2 reps short of failure."),
            Ex(name: "Cable lateral raise", sets: 4, reps: "10-15", tip: "Lead with the elbow."),
            Ex(name: "Reverse pec-deck fly", sets: 3, reps: "12-15", tip: "Rear delts, slow lowering."),
            Ex(name: "Face pull", sets: 3, reps: "12-15", tip: "Pull to forehead, squeeze 1 sec."),
            Ex(name: "Cable crunch", sets: 3, reps: "10-15", tip: "Round the spine, add weight over time.")]),
        "Tue": ("Back and abs", [
            Ex(name: "Pull-up or lat pulldown", sets: 4, reps: "6-10", tip: "Full stretch at the bottom."),
            Ex(name: "Chest-supported row", sets: 3, reps: "8-12", tip: "Keeps the lower back out of it."),
            Ex(name: "Hanging leg raise", sets: 4, reps: "8-15", tip: "Curl the pelvis up, no swinging."),
            Ex(name: "Ab wheel rollout", sets: 3, reps: "8-12", tip: "Ribs down, glutes tight."),
            Ex(name: "Dumbbell shrug", sets: 2, reps: "12-15", tip: "Traps help frame the shoulders.")]),
        "Wed": ("Legs", [
            Ex(name: "Goblet or barbell squat", sets: 4, reps: "6-10", tip: "Controlled down, drive up."),
            Ex(name: "Bulgarian split squat", sets: 3, reps: "8-12", tip: "Per leg."),
            Ex(name: "Seated leg curl", sets: 3, reps: "10-15", tip: "Hamstrings without deadlifts."),
            Ex(name: "Leg press", sets: 3, reps: "10-15", tip: "Full range."),
            Ex(name: "Standing calf raise", sets: 4, reps: "10-15", tip: "Pause at the stretch.")]),
        "Thu": ("Shoulders: volume", [
            Ex(name: "Landmine press", sets: 4, reps: "8-10", tip: "Easy on the joints, great for delts."),
            Ex(name: "Dumbbell lateral raise", sets: 5, reps: "12-20", tip: "Last set: drop weight and keep going."),
            Ex(name: "Rear delt cable fly", sets: 4, reps: "12-20", tip: "Light weight, strict form."),
            Ex(name: "Cable Y-raise", sets: 3, reps: "12-15", tip: "Lower traps and delts."),
            Ex(name: "Hanging knee raise", sets: 3, reps: "12-20", tip: "Slow and controlled.")]),
        "Fri": ("Pull and abs", [
            Ex(name: "Neutral-grip pull-up or pulldown", sets: 4, reps: "6-10", tip: "Elbows to hips."),
            Ex(name: "One-arm dumbbell row", sets: 3, reps: "8-12", tip: "Per arm."),
            Ex(name: "Cable crunch", sets: 4, reps: "10-15", tip: "Heavier than Monday."),
            Ex(name: "Dumbbell curl", sets: 3, reps: "10-12", tip: "Quick arm pump.")]),
        "Sat": ("Delts, legs, abs", [
            Ex(name: "Machine or dumbbell shoulder press", sets: 3, reps: "8-12", tip: "Moderate weight."),
            Ex(name: "Lateral raise", sets: 4, reps: "15-20", tip: "Pump work."),
            Ex(name: "Front squat or leg press", sets: 3, reps: "8-12", tip: "Keep it smooth."),
            Ex(name: "Reverse crunch", sets: 3, reps: "12-20", tip: "Lift hips, don't swing.")]),
        "Sun": ("Rest and mobility", [])
    ]
    private static let recoverySession: [Ex] = [
        Ex(name: "Easy 20-30 min walk", sets: 1, reps: "", tip: "Keep heart rate low."),
        Ex(name: "Band pull-aparts", sets: 2, reps: "15", tip: "Light shoulder blood flow."),
        Ex(name: "Dead bug", sets: 2, reps: "8 per side", tip: "Core without fatigue."),
        Ex(name: "Shoulder and hip mobility", sets: 1, reps: "8 min", tip: "Slow breathing.")
    ]

    @State private var manualRecovery: Double = 50
    @State private var useManual = false
    @State private var weightText: [String: String] = [:]
    @State private var repsText: [String: String] = [:]
    @State private var refresh = 0
    @State private var creatine = UserDefaults.standard.object(forKey: "dl.creatine") as? Bool ?? true

    private var dayName: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"
        return f.string(from: Date())
    }
    private var dayKey: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private var strapRecovery: Double? { Repository.widgetAnchor(days: repo.days)?.recovery }
    private var recovery: Double? { useManual ? manualRecovery : strapRecovery }

    private var zone: (name: String, color: Color) {
        guard let r = recovery else { return ("No score yet", .blue) }
        if r >= 67 { return ("Green", .green) }
        if r >= 34 { return ("Yellow", .yellow) }
        return ("Red", .red)
    }

    private var today: (title: String, ex: [Ex], note: String) {
        let base = Self.plan[dayName] ?? ("Rest", [])
        guard let r = recovery else { return (base.title, base.ex, "Full plan until your strap scores today.") }
        if r >= 67 { return (base.title, base.ex, "Full plan. Push each set to 1-2 reps from failure.") }
        if r >= 34 {
            return (base.title, base.ex.map { Ex(name: $0.name, sets: max(1, $0.sets - 1), reps: $0.reps, tip: $0.tip) },
                    "One fewer set per exercise. Stop 2-3 reps short of failure.")
        }
        return ("Recovery day", Self.recoverySession, "Low recovery. Skip heavy lifting, rest is when you adapt.")
    }

    private func top(_ reps: String) -> Int {
        let p = reps.split(separator: "-"); return p.count == 2 ? (Int(p[1]) ?? 0) : 0
    }
    private func last(_ name: String) -> Logged? {
        guard let d = UserDefaults.standard.data(forKey: "dl.lw." + name) else { return nil }
        return try? JSONDecoder().decode(Logged.self, from: d)
    }
    private func suggestion(_ e: Ex) -> String {
        guard let l = last(e.name) else { return "First time: pick a weight you can do for \(e.reps) with 2 reps left." }
        let msg = "Last: \(fmt(l.w)) lb x \(l.r). "
        if let r = recovery, r < 67 { return msg + "Yellow recovery, try \(fmt((l.w * 0.9 / 2.5).rounded() * 2.5)) lb." }
        if l.r >= top(e.reps) { return msg + "Hit the top reps, go to \(fmt(l.w + (l.w < 40 ? 2.5 : 5))) lb." }
        return msg + "Same weight, aim for \(l.r + 1)+ reps."
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func save(_ e: Ex) {
        guard let w = Double(weightText[e.name] ?? ""), let r = Int(repsText[e.name] ?? "") else { return }
        if let d = try? JSONEncoder().encode(Logged(w: w, r: r)) { UserDefaults.standard.set(d, forKey: "dl.lw." + e.name) }
        weightText[e.name] = ""; repsText[e.name] = ""; refresh += 1
    }

    private var waterMl: Int { UserDefaults.standard.integer(forKey: "dl.water." + dayKey) }
    private var waterGoal: Int { 2500 + (creatine ? 500 : 0) + (dayName == "Sun" ? 0 : 500) }
    private func addWater(_ ml: Int) {
        UserDefaults.standard.set(max(0, waterMl + ml), forKey: "dl.water." + dayKey); refresh += 1
    }

    var body: some View {
        let _ = refresh
        let t = today
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Train").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(recovery.map { "\(Int($0))%" } ?? "--").font(.system(size: 54, weight: .bold)).foregroundColor(zone.color)
                        Text(zone.name).font(.headline).foregroundColor(zone.color)
                    }
                    Text(useManual ? "Using the number you set below." : "Charge score from your strap.")
                        .font(.footnote).foregroundColor(.secondary)
                    Toggle("Set recovery manually", isOn: $useManual)
                    if useManual { Slider(value: $manualRecovery, in: 0...100, step: 1) }
                }
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                Text(t.title).font(.title2.bold())
                Text(t.note).font(.subheadline).foregroundColor(.secondary)

                ForEach(t.ex, id: \.name) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(e.name).font(.headline)
                            Spacer()
                            Text("\(e.sets)" + (e.reps.isEmpty ? "" : " x \(e.reps)")).font(.subheadline.bold())
                        }
                        Text(e.tip).font(.footnote).foregroundColor(.secondary)
                        if top(e.reps) > 0 && (recovery ?? 100) >= 34 {
                            Text(suggestion(e)).font(.footnote)
                            HStack {
                                TextField("lb", text: Binding(get: { weightText[e.name] ?? "" }, set: { weightText[e.name] = $0 }))
                                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 70)
                                TextField("reps", text: Binding(get: { repsText[e.name] ?? "" }, set: { repsText[e.name] = $0 }))
                                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 70)
                                Button("Log") { save(e) }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                Text("Water").font(.title2.bold())
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(waterMl) of \(waterGoal) ml").font(.headline)
                    ProgressView(value: min(1, Double(waterMl) / Double(waterGoal)))
                    HStack {
                        Button("+250 ml") { addWater(250) }.buttonStyle(.borderedProminent)
                        Button("+500 ml") { addWater(500) }.buttonStyle(.borderedProminent)
                        Button("Undo") { addWater(-250) }.buttonStyle(.bordered)
                    }
                    Toggle("I take 5 g creatine daily", isOn: $creatine)
                        .onChange(of: creatine) { _, v in UserDefaults.standard.set(v, forKey: "dl.creatine") }
                    Text("Goal: 2500 ml base for 155 lb, +500 ml creatine, +500 ml on training days.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .task { await repo.refresh() }
    }
}
#endif
