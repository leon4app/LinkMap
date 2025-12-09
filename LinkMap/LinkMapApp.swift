// SwiftUI 应用入口。使用 WindowGroup 承载主界面，
// 通过 LinkMapAnalyzer 处理文件选择、解析统计与结果输出。
import SwiftUI

@main
struct LinkMapApp: App {
    @StateObject var model = LinkMapModel()
    private var analyzer: LinkMapAnalyzer
    init() {
        // 将模型与解析器初始化，并在启动时恢复持久化的用户状态
        let m = LinkMapModel()
        _model = StateObject(wrappedValue: m)
        analyzer = LinkMapAnalyzer(model: m)
        analyzer.loadPersistedState()
    }

    var body: some Scene {
        WindowGroup {
            // 主界面：模型状态驱动，操作通过闭包委托给解析器
            LinkMapRootView(
                model: model,
                onChooseFile: { analyzer.chooseFile() },
                onAnalyze: { analyzer.analyze() },
                onOutput: { analyzer.outputFile() },
                onFileDropped: { analyzer.didDragFileUrl($0) },
                onGroupChanged: { analyzer.renderCached(withGroup: $0) }
            )
            .frame(minWidth: 700, minHeight: 520)
        }
    }
}
