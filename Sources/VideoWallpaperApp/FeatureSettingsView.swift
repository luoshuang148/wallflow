import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WallpaperCore
import WallpaperRuntime

@MainActor
struct FeatureSettingsView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var startup: LoginStartupModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName = ""
    @State private var groupNames: [String: String] = [:]
    @State private var playlist = PlaylistSettings()
    @State private var loadedDraft = false
    @State private var playlistSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("壁纸库与自动播放").font(.title2.weight(.semibold))
            TabView {
                groupsTab.tabItem { Label("分组", systemImage: "folder") }
                playlistTab.tabItem { Label("轮播与日夜", systemImage: "repeat") }
                rulesTab.tabItem { Label("应用规则", systemImage: "app.badge") }
                startupTab.tabItem { Label("登录启动", systemImage: "power") }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
            }
            if !embedded {
                HStack {
                    Spacer()
                    Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width:650,height:embedded ? 520 : 560)
        .onAppear {
            if !loadedDraft {
                playlist = model.state.playlist
                groupNames = Dictionary(uniqueKeysWithValues: model.state.organization.groups.map { ($0.id, $0.name) })
                loadedDraft = true
            }
            startup.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startup.refresh()
        }
        .onChange(of: playlist) { _, _ in playlistSaved = false }
    }

    private var groupsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("新分组名称", text: $newGroupName).textFieldStyle(.roundedBorder)
                        .onSubmit(addGroup)
                    Button("添加分组", action: addGroup)
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.state.organization.groups.isEmpty {
                    Text("暂无分组")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.state.organization.groups) { group in
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        TextField("分组名称", text: Binding(
                            get: { groupNames[group.id] ?? group.name },
                            set: { groupNames[group.id] = $0 }
                        )).textFieldStyle(.roundedBorder)
                        Button("重命名") { renameGroup(group.id) }
                        Button("删除", role: .destructive) {
                            var value = model.state.organization
                            value.deleteGroup(group.id)
                            model.setOrganization(value)
                            groupNames.removeValue(forKey: group.id)
                        }
                    }
                }
            }.padding(18)
        }
    }

    private var playlistTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("启用自动切换", isOn: $playlist.enabled).toggleStyle(.switch)
                Picker("切换方式", selection: $playlist.mode) {
                    Text("按间隔轮播").tag(PlaylistMode.interval)
                    Text("按日夜切换").tag(PlaylistMode.dayNight)
                }.pickerStyle(.segmented)
                displayPicker
                if playlist.mode == .interval { intervalOptions }
                else { dayNightOptions }
                HStack {
                    if playlistSaved {
                        Label("轮播设置已保存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("保存轮播设置") {
                        model.setPlaylist(playlist)
                        playlistSaved = model.state.playlist == playlist
                    }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
            }.padding(18)
        }
    }

    private var displayPicker: some View {
        Picker("切换屏幕", selection: $playlist.targetDisplayID) {
            Text("所有屏幕").tag(nil as String?)
            ForEach(model.displays) { display in Text(display.name).tag(Optional(display.id)) }
            if let id = playlist.targetDisplayID, !model.displays.contains(where: { $0.id == id }) {
                Text("暂未连接的屏幕").tag(Optional(id))
            }
        }
    }

    private var intervalOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("切换间隔")
                TextField("分钟", value: $playlist.intervalMinutes, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                Text("分钟（1–1440）").foregroundStyle(.secondary)
                Spacer()
            }
            Picker("播放顺序", selection: $playlist.order) {
                Text("按列表顺序").tag(PlaylistOrder.sequential)
                Text("随机播放").tag(PlaylistOrder.random)
            }
            Text("选择至少两张壁纸").font(.callout.weight(.medium))
            if model.state.projects.isEmpty {
                Text("请先导入壁纸。") .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.state.projects) { project in
                Toggle(model.displayName(for:project), isOn: Binding(
                    get: { playlist.projectIDs.contains(project.id) },
                    set: { included in
                        if included {
                            if !playlist.projectIDs.contains(project.id) { playlist.projectIDs.append(project.id) }
                        } else { playlist.projectIDs.removeAll { $0 == project.id } }
                    }
                )).toggleStyle(.checkbox)
            }
        }
    }

    private var dayNightOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            projectPicker("日间壁纸", selection: $playlist.dayProjectID)
            DatePicker("日间开始", selection: timeBinding(\.dayStartMinute), displayedComponents: .hourAndMinute)
            Divider()
            projectPicker("夜间壁纸", selection: $playlist.nightProjectID)
            DatePicker("夜间开始", selection: timeBinding(\.nightStartMinute), displayedComponents: .hourAndMinute)
        }
    }

    private func projectPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("请选择壁纸").tag(nil as String?)
            ForEach(model.state.projects) { project in Text(model.displayName(for:project)).tag(Optional(project.id)) }
            if let id = selection.wrappedValue, !model.state.projects.contains(where: { $0.id == id }) {
                Text("壁纸已移除，请重新选择").tag(Optional(id))
            }
        }
    }

    private func timeBinding(_ key: WritableKeyPath<PlaylistSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = playlist[keyPath: key]
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60)) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            playlist[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    private var rulesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button("添加应用…", action: addApplication)
                }
                if model.state.applicationRules.isEmpty {
                    Text("暂无应用规则")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.state.applicationRules) { rule in ruleRow(rule) }
            }.padding(18)
        }
    }

    private func ruleRow(_ rule: ApplicationRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(rule.name, isOn: ruleBinding(rule.id, \.enabled, fallback: rule.enabled)).toggleStyle(.checkbox)
                Spacer()
                Button("删除", role: .destructive) {
                    model.setApplicationRules(model.state.applicationRules.filter { $0.id != rule.id })
                }
            }
            HStack(spacing: 14) {
                Picker("当应用", selection: ruleBinding(rule.id, \.condition, fallback: rule.condition)) {
                    Text("正在运行").tag(ApplicationRuleCondition.running)
                    Text("位于前台").tag(ApplicationRuleCondition.frontmost)
                }
                Picker("壁纸", selection: ruleBinding(rule.id, \.action, fallback: rule.action)) {
                    Text("静音").tag(ApplicationRuleAction.mute)
                    Text("暂停").tag(ApplicationRuleAction.pause)
                    Text("停止并释放资源").tag(ApplicationRuleAction.stop)
                }
            }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func ruleBinding<Value>(_ id: String, _ key: WritableKeyPath<ApplicationRule, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: {
            model.state.applicationRules.first(where: { $0.id == id })?[keyPath: key] ?? fallback
        }, set: { value in
            var rules = model.state.applicationRules
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            rules[index][keyPath: key] = value
            model.setApplicationRules(rules)
        })
    }

    private var startupTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("登录 Mac 后自动播放壁纸", isOn: Binding(
                get: { startup.enabled || startup.needsApproval },
                set: { startup.setEnabled($0) }
            )).toggleStyle(.switch)
            Text("首次打开默认启用；关闭后会保留你的选择。登录时不会打开管理窗口或显示菜单栏图标。")
                .font(.callout).foregroundStyle(.secondary)
            if startup.needsApproval {
                Label("需要在系统设置中允许登录启动", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Button("打开登录项设置") { startup.openSettings() }
            } else {
                Label(startup.enabled ? "已启用登录启动" : "登录启动已关闭", systemImage: startup.enabled ? "checkmark.circle" : "minus.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = startup.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            Spacer()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addGroup() {
        var value = model.state.organization
        do {
            let id = try value.addGroup(newGroupName)
            model.setOrganization(value)
            if model.state.organization.groups.contains(where: { $0.id == id }) {
                groupNames[id] = value.groups.first(where: { $0.id == id })?.name
                newGroupName = ""
            }
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func renameGroup(_ id: String) {
        var value = model.state.organization
        do {
            try value.renameGroup(id, name: groupNames[id] ?? "")
            model.setOrganization(value)
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "添加规则"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else {
                    model.errorMessage = "无法识别所选应用，请选择有效的 Mac 应用。"
                    return
                }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                var rules = model.state.applicationRules
                rules.append(ApplicationRule(bundleID: id, name: name))
                model.setApplicationRules(rules)
            }
        }
    }
}
