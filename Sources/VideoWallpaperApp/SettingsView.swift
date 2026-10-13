import SwiftUI
import WallpaperRuntime

struct SettingsView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var startup: LoginStartupModel
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .library
    private enum Page: String, CaseIterable {
        case library = "壁纸库与自动播放"
        case performance = "性能与电源"
        var symbol: String { self == .library ? "slider.horizontal.3" : "leaf" }
    }
    var body: some View {
        VStack(spacing:12) {
            HStack {
                Text("设置").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Divider()
            HStack(alignment:.top,spacing:0) {
                VStack(spacing:8) {
                    ForEach(Page.allCases,id:\.self) { item in
                        Button { page = item } label: {
                            Label(item.rawValue,systemImage:item.symbol)
                                .font(.system(size:12,weight:.medium))
                                .frame(maxWidth:.infinity,alignment:.leading).padding(12)
                                .contentShape(Rectangle())
                                .background(page == item ? Color.accentColor.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.trailing,12).frame(width:190)
                Divider()
                ZStack(alignment:.top) {
                    FeatureSettingsView(model:model,startup:startup,embedded:true)
                        .opacity(page == .library ? 1 : 0)
                        .allowsHitTesting(page == .library).accessibilityHidden(page != .library)
                    PerformanceView(model:model,embedded:true)
                        .opacity(page == .performance ? 1 : 0)
                        .allowsHitTesting(page == .performance).accessibilityHidden(page != .performance)
                }.frame(width:650,height:530,alignment:.top)
            }
        }.padding(20).frame(width:900,height:620)
    }
}
