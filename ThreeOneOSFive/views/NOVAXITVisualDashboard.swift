import SwiftUI

/// NOVAXIT visual dashboard prototype.
/// This screen is presentation-only; its cards and preferences do not perform
/// file modification, injection, exploitation, or other device operations.
struct NOVAXITVisualDashboard: View {
    @State private var selectedTab: DashboardTab = .home
    @State private var soundEffects = true
    @State private var haptics = true
    @State private var notifications = false

    private let accent = Color(red: 0.55, green: 0.35, blue: 1.0)
    private let cyan = Color(red: 0.20, green: 0.78, blue: 1.0)
    private let background = Color(red: 0.035, green: 0.035, blue: 0.065)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 390)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        welcomeCard
                        sectionHeading("QUICK ACCESS", subtitle: "YOUR NOVAXIT SPACE")
                        quickAccessGrid
                        preferencesCard
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                tabBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [accent, cyan.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                Text("N")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NOVA")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white)
                Text("XIT CONTROL CENTER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.06), in: Circle())
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("PERSONAL DASHBOARD", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(cyan)
                Spacer()
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("READY")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("WELCOME TO")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.58))
                Text("NOVAXIT")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Text("Everything you need, in one place.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                Text("EXPLORE YOUR CONTROL CENTER")
            }
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(LinearGradient(colors: [accent, Color(red: 0.31, green: 0.28, blue: 0.85)], startPoint: .leading, endPoint: .trailing), in: Capsule())
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.22), Color(red: 0.07, green: 0.08, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 170, height: 170)
                    .offset(x: 45, y: -62)
                Circle()
                    .stroke(cyan.opacity(0.14), lineWidth: 1)
                    .frame(width: 125, height: 125)
                    .offset(x: 22, y: -40)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(accent.opacity(0.35), lineWidth: 1))
    }

    private var quickAccessGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            AccessTile(title: "FILES", subtitle: "File overview", icon: "folder.fill", tint: accent)
            AccessTile(title: "INFO", subtitle: "About NOVAXIT", icon: "info.circle.fill", tint: cyan)
            AccessTile(title: "SYSTEM", subtitle: "Device details", icon: "cpu.fill", tint: Color(red: 0.28, green: 0.78, blue: 0.63))
            AccessTile(title: "TUTORIAL", subtitle: "Helpful guides", icon: "play.rectangle.fill", tint: Color(red: 1.0, green: 0.63, blue: 0.28))
            AccessTile(title: "STORE", subtitle: "Explore items", icon: "bag.fill", tint: Color(red: 0.94, green: 0.39, blue: 0.67))
            AccessTile(title: "SUPPORT", subtitle: "Help center", icon: "message.fill", tint: Color(red: 0.47, green: 0.65, blue: 1.0))
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("PREFERENCES", subtitle: "CUSTOMIZE YOUR EXPERIENCE")
            PreferenceRow(title: "Sound effects", subtitle: "Interface audio feedback", icon: "speaker.wave.2.fill", isOn: $soundEffects, tint: accent)
            Divider().overlay(.white.opacity(0.07))
            PreferenceRow(title: "Haptic feedback", subtitle: "Touch response", icon: "hand.tap.fill", isOn: $haptics, tint: cyan)
            Divider().overlay(.white.opacity(0.07))
            PreferenceRow(title: "Notifications", subtitle: "General app alerts", icon: "bell.badge.fill", isOn: $notifications, tint: .orange)
        }
        .padding(17)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Text("NOVAXIT")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.5)
            Spacer()
            Text("VISUAL PREVIEW")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.2)
        }
        .foregroundStyle(.white.opacity(0.28))
        .padding(.top, 2)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.38))
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundStyle(selectedTab == tab ? accent : .white.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 13)
                    .padding(.bottom, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case home, info, system, tutorial, store
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var icon: String {
        switch self {
        case .home: "house"
        case .info: "info.circle"
        case .system: "cpu"
        case .tutorial: "play.rectangle"
        case .store: "bag"
        }
    }
    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .info: "info.circle.fill"
        case .system: "cpu.fill"
        case .tutorial: "play.rectangle.fill"
        case .store: "bag.fill"
        }
    }
}

private struct AccessTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 39, height: 39)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(tint.opacity(0.23), lineWidth: 1))
    }
}

private struct PreferenceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(tint)
                .scaleEffect(0.82, anchor: .trailing)
        }
    }
}
