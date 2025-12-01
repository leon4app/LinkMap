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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("文件路径")
                Text(model.filePath.isEmpty ? "未选择" : model.filePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("选择文件", action: onChooseFile)
            }
            HStack(spacing: 8) {
                TextField("二进制规则 (正则，支持 +)", text: Binding(get: { model.binaryRule }, set: { model.binaryRule = $0 }))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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
    }
}

@objc public class LinkMapHosting: NSObject {
    @objc public static func hostingView(model: LinkMapModel,
                                  onChooseFile: @escaping () -> Void,
                                  onAnalyze: @escaping () -> Void,
                                  onOutput: @escaping () -> Void,
                                  onFileDropped: @escaping (String) -> Void) -> NSView {
        let root = LinkMapRootView(model: model, onChooseFile: onChooseFile, onAnalyze: onAnalyze, onOutput: onOutput, onFileDropped: onFileDropped)
        let hosting = NSHostingView(rootView: root)
        return hosting
    }
}
