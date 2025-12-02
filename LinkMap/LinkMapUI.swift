import SwiftUI
import AppKit

@objcMembers public class LinkMapModel: NSObject, ObservableObject {
    @Published public var binaryRule: String = ""
    @Published public var assetsRule: String = ""
    @Published public var syncRuleOn: Bool = false
    @Published public var ignoreEmbeddedOn: Bool = false
    @Published public var ignoreBundleOn: Bool = false
    @Published public var groupParseOn: Bool = true
    @Published public var result: NSAttributedString?
    @Published public var filePath: String = ""
    @Published public var filePathHistory: [String] = []
    @Published public var binaryRuleHistory: [String] = []
    @Published public var assetsRuleHistory: [String] = []
    @Published public var ignoreAOn: Bool = false
    @Published public var ignoreOOn: Bool = false
    @Published public var ignoreTbdOn: Bool = false
    @Published public var ignoreDylibOn: Bool = false
    @Published public var ignoreSpacePrefixOn: Bool = false
    @Published public var warningText: String? = nil
    @Published public var rulePresets: [[String: Any]] = []
}

struct ResultScrollTextViewRepresentable: NSViewRepresentable {
    var attributedText: NSAttributedString?
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .textBackgroundColor
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tv = nsView.documentView as? NSTextView {
            tv.textStorage?.setAttributedString(attributedText ?? NSAttributedString(string: ""))
        }
    }
}

struct LinkMapRootView: View {
    @ObservedObject var model: LinkMapModel
    let onChooseFile: () -> Void
    let onAnalyze: () -> Void
    let onOutput: () -> Void
    let onFileDropped: (String) -> Void
    let onGroupChanged: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup("使用说明") {
                Text("1. 在 Xcode 的 Build Settings 开启 Write Link Map File，并指定保存位置")
                Text("2. 构建后选择生成的 Link Map 文件 (txt)")
                Text("3. 输入二进制规则与资源规则，或使用预设")
                Text("4. 配置过滤开关与分组解析，点击开始")
                Text("5. 结果支持输出为 RTF 文件")
            }
            HStack(spacing: 8) {
                Text("文件路径")
                Text(model.filePath.isEmpty ? "未选择" : model.filePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Menu("历史") {
                    ForEach(model.filePathHistory, id: \.self) { p in
                        Button(p) { onFileDropped(p) }
                    }
                }
                Spacer()
                Button("选择文件", action: onChooseFile)
            }
            if let warn = model.warningText, !warn.isEmpty {
                Text(warn)
                    .foregroundColor(.red)
            }
            HStack(spacing: 8) {
                TextField("二进制规则 (正则，支持 +)", text: Binding(get: { model.binaryRule }, set: { model.binaryRule = $0 }))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Menu("历史") {
                    ForEach(model.binaryRuleHistory, id: \.self) { r in
                        Button(r) { model.binaryRule = r }
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("资源规则 (可留空)", text: Binding(get: { model.assetsRule }, set: { model.assetsRule = $0 }))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Menu("历史") {
                    ForEach(model.assetsRuleHistory, id: \.self) { r in
                        Button(r) { model.assetsRule = r }
                    }
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Toggle("资源继承二进制规则", isOn: Binding(get: { model.syncRuleOn }, set: { model.syncRuleOn = $0 }))
                Toggle("不统计嵌入 framework/dylib", isOn: Binding(get: { model.ignoreEmbeddedOn }, set: { model.ignoreEmbeddedOn = $0 }))
                Toggle("不统计 bundle 资源", isOn: Binding(get: { model.ignoreBundleOn }, set: { model.ignoreBundleOn = $0 }))
                Spacer()
                Toggle("分组解析", isOn: Binding(get: { model.groupParseOn }, set: { model.groupParseOn = $0 }))
                Button("开始", action: onAnalyze)
                Button("输出文件", action: onOutput)
            }
            HStack(spacing: 8) {
                Button("保存预设") {
                    let preset: [String: Any] = [
                        "binaryRule": model.binaryRule,
                        "assetsRule": model.assetsRule,
                        "syncRuleOn": model.syncRuleOn,
                        "ignoreEmbeddedOn": model.ignoreEmbeddedOn,
                        "ignoreBundleOn": model.ignoreBundleOn,
                        "id": UUID().uuidString,
                        "title": (model.assetsRule.isEmpty ? model.binaryRule : (model.binaryRule + " | " + model.assetsRule))
                    ]
                    var arr = model.rulePresets
                    arr.removeAll { ($0["binaryRule"] as? String == preset["binaryRule"] as? String)
                                    && ($0["assetsRule"] as? String == preset["assetsRule"] as? String)
                                    && ($0["syncRuleOn"] as? Bool == preset["syncRuleOn"] as? Bool)
                                    && ($0["ignoreEmbeddedOn"] as? Bool == preset["ignoreEmbeddedOn"] as? Bool)
                                    && ($0["ignoreBundleOn"] as? Bool == preset["ignoreBundleOn"] as? Bool) }
                    arr.insert(preset, at: 0)
                    if arr.count > 10 { arr.removeSubrange(10..<arr.count) }
                    UserDefaults.standard.set(arr, forKey: "LM_RulePresets")
                    model.rulePresets = arr
                }
                Menu("加载预设") {
                    ForEach(Array(model.rulePresets.enumerated()), id: \.offset) { _, item in
                        let title = (item["title"] as? String) ?? "未命名预设"
                        Button(title) {
                            model.binaryRule = (item["binaryRule"] as? String) ?? ""
                            model.assetsRule = (item["assetsRule"] as? String) ?? ""
                            model.syncRuleOn = (item["syncRuleOn"] as? Bool) ?? false
                            model.ignoreEmbeddedOn = (item["ignoreEmbeddedOn"] as? Bool) ?? false
                            model.ignoreBundleOn = (item["ignoreBundleOn"] as? Bool) ?? false
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Text("过滤选项")
                Toggle(".a", isOn: Binding(get: { model.ignoreAOn }, set: { model.ignoreAOn = $0 }))
                Toggle(".o", isOn: Binding(get: { model.ignoreOOn }, set: { model.ignoreOOn = $0 }))
                Toggle(".tbd", isOn: Binding(get: { model.ignoreTbdOn }, set: { model.ignoreTbdOn = $0 }))
                Toggle(".dylib", isOn: Binding(get: { model.ignoreDylibOn }, set: { model.ignoreDylibOn = $0 }))
                Toggle("空格前缀", isOn: Binding(get: { model.ignoreSpacePrefixOn }, set: { model.ignoreSpacePrefixOn = $0 }))
                Spacer()
            }
            Divider()
            ResultScrollTextViewRepresentable(attributedText: model.result)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                    DispatchQueue.main.async { onFileDropped(url.path) }
                } else if let url = item as? URL {
                    DispatchQueue.main.async { onFileDropped(url.path) }
                }
            }
            return true
        }
        .onChange(of: model.groupParseOn) { newValue in
            onGroupChanged(newValue)
        }
        .onAppear {
            model.rulePresets = (UserDefaults.standard.array(forKey: "LM_RulePresets") as? [[String: Any]]) ?? []
        }
    }
}

@objc public class LinkMapHosting: NSObject {
    @objc public static func hostingView(model: LinkMapModel,
                                  onChooseFile: @escaping () -> Void,
                                  onAnalyze: @escaping () -> Void,
                                  onOutput: @escaping () -> Void,
                                  onFileDropped: @escaping (String) -> Void,
                                  onGroupChanged: @escaping (Bool) -> Void) -> NSView {
        let root = LinkMapRootView(model: model, onChooseFile: onChooseFile, onAnalyze: onAnalyze, onOutput: onOutput, onFileDropped: onFileDropped, onGroupChanged: onGroupChanged)
        let hosting = NSHostingView(rootView: root)
        return hosting
    }
}
