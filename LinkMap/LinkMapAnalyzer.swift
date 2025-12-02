// 核心解析与统计逻辑，需使用 AppKit/SwiftUI 类型（NSOpenPanel、NSAttributedString、NSAlert）
import Cocoa
import SwiftUI

/// Link Map 解析器：负责文件选择、解析统计、结果渲染与持久化
final class LinkMapAnalyzer {
    let model: LinkMapModel
    private var linkMapFileURL: URL?
    private var linkMapContent: String = ""
    private var cachedSortedSymbols: [SymbolModel] = []

    init(model: LinkMapModel) {
        self.model = model
    }

    /// 恢复持久化的规则、开关与历史列表到模型状态
    func loadPersistedState() {
        let ud = UserDefaults.standard
        model.binaryRule = ud.string(forKey: "LM_BinaryRule") ?? ""
        model.assetsRule = ud.string(forKey: "LM_AssetsRule") ?? ""
        model.syncRuleOn = ud.bool(forKey: "LM_SyncRuleOn")
        model.ignoreEmbeddedOn = ud.bool(forKey: "LM_IgnoreEmbedded")
        model.ignoreBundleOn = ud.bool(forKey: "LM_IgnoreBundle")
        model.filePathHistory = (ud.array(forKey: "LM_FileHistory") as? [String]) ?? []
        model.binaryRuleHistory = (ud.array(forKey: "LM_BinaryRuleHistory") as? [String]) ?? []
        model.assetsRuleHistory = (ud.array(forKey: "LM_AssetsRuleHistory") as? [String]) ?? []
        model.ignoreAOn = ud.bool(forKey: "LM_IgnoreA")
        model.ignoreOOn = ud.bool(forKey: "LM_IgnoreO")
        model.ignoreTbdOn = ud.bool(forKey: "LM_IgnoreTbd")
        model.ignoreDylibOn = ud.bool(forKey: "LM_IgnoreDylib")
        model.ignoreSpacePrefixOn = ud.bool(forKey: "LM_IgnoreSpacePrefix")
        model.rulePresets = (ud.array(forKey: "LM_RulePresets") as? [[String: Any]]) ?? []
    }

    /// 处理拖拽的文件路径，更新当前文件并维护历史列表
    func didDragFileUrl(_ path: String) {
        let url = URL(fileURLWithPath: path)
        linkMapFileURL = url
        model.filePath = url.path
        let ud = UserDefaults.standard
        var old = (ud.array(forKey: "LM_FileHistory") as? [String]) ?? []
        old.removeAll { $0 == url.path }
        old.insert(url.path, at: 0)
        if old.count > 10 { old.removeSubrange(10..<old.count) }
        ud.set(old, forKey: "LM_FileHistory")
        model.filePathHistory = old
    }

    /// 打开系统面板选择 Link Map 文本文件，更新当前文件并维护历史列表
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = false
        panel.canChooseFiles = true
        panel.begin { [weak self] result in
            guard let self = self else { return }
            if result == .OK, let document = panel.urls.first {
                self.linkMapFileURL = document
                self.model.filePath = document.path
                let ud = UserDefaults.standard
                var old = (ud.array(forKey: "LM_FileHistory") as? [String]) ?? []
                old.removeAll { $0 == document.path }
                old.insert(document.path, at: 0)
                if old.count > 10 { old.removeSubrange(10..<old.count) }
                ud.set(old, forKey: "LM_FileHistory")
                self.model.filePathHistory = old
            }
        }
    }

    /// 异步解析与统计：读取 Link Map → 解析符号 → 采集嵌入/资源 → 构建结果并发布到 UI
    func analyze() {
        guard let url = linkMapFileURL, FileManager.default.fileExists(atPath: url.path) else {
            showAlert("请选择正确的Link Map文件路径")
            return
        }
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let content = (try? String(contentsOf: url, encoding: .macOSRoman)) ?? ""
            self.linkMapContent = content
            guard self.checkContent(content) else {
                DispatchQueue.main.async { self.showAlert("Link Map文件格式有误") }
                return
            }
            let hasPreview = (content.range(of: "PreviewsJIT", options: .caseInsensitive) != nil)
                || (content.range(of: "__debug_dylib", options: .caseInsensitive) != nil)
                || (content.range(of: ".debug.dylib", options: .caseInsensitive) != nil)
            DispatchQueue.main.async {
                self.model.warningText = hasPreview ? "检测到预览/调试注入，静态链接统计可能偏少；嵌入与资源分项仍可用" : nil
            }

            let symbolMap = self.symbolMapFromContent(content)
            let symbols = Array(symbolMap.values)
            let sortedSymbols = self.sortSymbols(symbols)
            self.cachedSortedSymbols = sortedSymbols

            if self.model.groupParseOn {
                self.buildCombinationResult(with: sortedSymbols)
            } else {
                self.buildResult(with: sortedSymbols)
            }

            DispatchQueue.main.async {
                self.model.result = self.currentResult
            }
        }
    }

    /// 在已有解析结果基础上切换分组模式并重新渲染
    func renderCached(withGroup on: Bool) {
        guard !cachedSortedSymbols.isEmpty else { return }
        if on {
            buildCombinationResult(with: cachedSortedSymbols)
        } else {
            buildResult(with: cachedSortedSymbols)
        }
        DispatchQueue.main.async { self.model.result = self.currentResult }
    }

    /// 导出当前结果为 RTF 文件到用户选择的目录
    func outputFile() {
        let panel = NSOpenPanel()
        panel.prompt = "OK"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = false
        panel.canChooseFiles = false
        panel.begin { [weak self] result in
            guard let self = self else { return }
            if result == .OK, let dirPath = panel.urls.first {
                let filePath = dirPath.appendingPathComponent("linkMap.rtf").path
                let ns = self.currentResult
                let data = try? ns.data(from: NSRange(location: 0, length: ns.length), documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ])
                try? data?.write(to: URL(fileURLWithPath: filePath))
            }
        }
    }

    // MARK: - Parsing & Result
    private var currentResult = NSMutableAttributedString(string: "")

    /// 解析 Link Map：遍历 # Object files 与 # Symbols 段，累计每个目标文件的符号大小
    private func symbolMapFromContent(_ content: String) -> [String: SymbolModel] {
        var map: [String: SymbolModel] = [:]
        let lines = content.components(separatedBy: "\n")
        var reachFiles = false
        var reachSymbols = false
        var reachSections = false
        for line in lines {
            if line.hasPrefix("#") {
                if line.hasPrefix("# Object files:") { reachFiles = true }
                else if line.hasPrefix("# Sections:") { reachSections = true }
                else if line.hasPrefix("# Symbols:") { reachSymbols = true }
                else if line.hasPrefix("# Dead Stripped Symbols:") { break }
            } else {
                if reachFiles && !reachSections && !reachSymbols {
                    if let r = line.range(of: "]") {
                        let symbol = SymbolModel()
                        symbol.file = String(line[line.index(after: r.lowerBound)...])
                        let key = String(line[..<line.index(after: r.lowerBound)])
                        map[key] = symbol
                    }
                } else if reachFiles && reachSections && reachSymbols {
                    let parts = line.components(separatedBy: "\t")
                    if parts.count == 3 {
                        let fileKeyAndName = parts[2]
                        let sizeStr = parts[1]
                        var size: UInt = 0
                        if sizeStr.lowercased().hasPrefix("0x") {
                            size = UInt(strtoul(sizeStr, nil, 16))
                        } else {
                            size = UInt(strtoul(sizeStr, nil, 10))
                        }
                        if let r = fileKeyAndName.range(of: "]") {
                            let key = String(fileKeyAndName[..<fileKeyAndName.index(after: r.lowerBound)])
                            if let symbol = map[key] { symbol.size &+= size }
                        }
                    }
                }
            }
        }
        return map
    }

    private func sortSymbols(_ symbols: [SymbolModel]) -> [SymbolModel] {
        symbols.sorted { (a, b) in if a.size == b.size { return false } else { return a.size > b.size } }
    }

    /// 构建普通模式结果：列表行 + 分项统计（二进制/资源）+ 合计
    private func buildResult(with symbols: [SymbolModel]) {
        currentResult = NSMutableAttributedString(string: "库大小\t\t库名称\r\n\r\n")
        let augmented = symbols
        let binaryPath = appBinaryPathFromContent(linkMapContent)
        let extra = extraSymbols(fromAppBinaryPath: binaryPath)
        var extraFrameworks: [SymbolModel] = []
        var extraBundles: [SymbolModel] = []
        for m in extra {
            if m.file.hasSuffix(".bundle") { extraBundles.append(m) } else { extraFrameworks.append(m) }
        }
        let binaryRule = model.binaryRule
        let assetsRule = (model.assetsRule.isEmpty && model.syncRuleOn) ? binaryRule : model.assetsRule
        let ignoreEmbedded = model.ignoreEmbeddedOn
        var binarySymbols: [SymbolModel] = ignoreEmbedded ? symbols : augmented
        if !ignoreEmbedded && !extraFrameworks.isEmpty { binarySymbols.append(contentsOf: extraFrameworks) }
        persistRules(binaryRule: binaryRule, assetsRule: assetsRule)
        let binaryTotal = analyze(binarySymbols, searchKey: binaryRule)
        let ignoreBundle = model.ignoreBundleOn
        let bundleTotal = ignoreBundle ? 0 : analyzeAssets(extraBundles, searchKey: assetsRule)
        let totalSize = binaryTotal &+ bundleTotal
        appendTotals(binaryTotal: binaryTotal, bundleTotal: bundleTotal, totalSize: totalSize)
    }

    /// 构建分组模式结果：按库名聚合后排序，附加分项与合计
    private func buildCombinationResult(with symbols: [SymbolModel]) {
        currentResult = NSMutableAttributedString(string: "库大小\t\t库名称\r\n\r\n")
        var combinationMap: [String: SymbolModel] = [:]
        for symbol in symbols {
            let name = URL(fileURLWithPath: symbol.file).lastPathComponent
            if name.hasSuffix(")"), let range = name.range(of: "(") {
                var component = String(name[..<range.lowerBound])
                if component.hasSuffix("]"), let r2 = component.range(of: "[") {
                    component = String(component[..<r2.lowerBound])
                }
                let comb = combinationMap[component] ?? SymbolModel()
                comb.size &+= symbol.size
                comb.file = component
                combinationMap[component] = comb
            } else {
                combinationMap[symbol.file] = symbol
            }
        }
        let combinationSymbols = Array(combinationMap.values)
        var sortedSymbols = sortSymbols(combinationSymbols)
        let binaryPath = appBinaryPathFromContent(linkMapContent)
        let extra = extraSymbols(fromAppBinaryPath: binaryPath)
        var extraFrameworks: [SymbolModel] = []
        var extraBundles: [SymbolModel] = []
        for m in extra {
            if m.file.hasSuffix(".bundle") { extraBundles.append(m) } else { extraFrameworks.append(m) }
        }
        let binaryRule = model.binaryRule
        let assetsRule = (model.assetsRule.isEmpty && model.syncRuleOn) ? binaryRule : model.assetsRule
        let ignoreEmbedded = model.ignoreEmbeddedOn
        if !ignoreEmbedded && !extraFrameworks.isEmpty {
            sortedSymbols = sortSymbols(sortedSymbols + extraFrameworks)
        }
        persistRules(binaryRule: binaryRule, assetsRule: assetsRule)
        let binaryTotal = analyze(sortedSymbols, searchKey: binaryRule)
        let ignoreBundle = model.ignoreBundleOn
        let bundleTotal = ignoreBundle ? 0 : analyzeAssets(extraBundles, searchKey: assetsRule)
        let totalSize = binaryTotal &+ bundleTotal
        appendTotals(binaryTotal: binaryTotal, bundleTotal: bundleTotal, totalSize: totalSize)
    }

    /// 从 Link Map 文本中提取编译产物路径（# Path:）
    private func appBinaryPathFromContent(_ content: String) -> String? {
        guard let range = content.range(of: "# Path:") else { return nil }
        let sub = String(content[range.upperBound...])
        if let nl = sub.firstIndex(of: "\n") { return String(sub[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines) }
        return sub.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 在 .app 目录采集嵌入的 framework/dylib 与 .bundle 资源的大小
    private func extraSymbols(fromAppBinaryPath binaryPath: String?) -> [SymbolModel] {
        guard let binaryPath, !binaryPath.isEmpty else { return [] }
        let appDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        let fm = FileManager.default
        var arr: [SymbolModel] = []
        let frameworksDir = URL(fileURLWithPath: appDir).appendingPathComponent("Frameworks").path
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: frameworksDir, isDirectory: &isDir), isDir.boolValue {
            let items = (try? fm.contentsOfDirectory(atPath: frameworksDir)) ?? []
            for item in items {
                let full = URL(fileURLWithPath: frameworksDir).appendingPathComponent(item).path
                if item.hasSuffix(".framework") {
                    let binName = URL(fileURLWithPath: item).deletingPathExtension().lastPathComponent
                    let binPath = URL(fileURLWithPath: full).appendingPathComponent(binName).path
                    let size = fileSize(atPath: binPath)
                    if size > 0 { let m = SymbolModel(); m.file = binPath; m.size = UInt(size); arr.append(m) }
                } else if item.hasSuffix(".dylib") {
                    let size = fileSize(atPath: full)
                    if size > 0 { let m = SymbolModel(); m.file = full; m.size = UInt(size); arr.append(m) }
                }
            }
        }
        let appItems = (try? fm.contentsOfDirectory(atPath: appDir)) ?? []
        for item in appItems where item.hasSuffix(".bundle") {
            let bundlePath = URL(fileURLWithPath: appDir).appendingPathComponent(item).path
            let size = directorySize(atPath: bundlePath)
            if size > 0 { let m = SymbolModel(); m.file = bundlePath; m.size = UInt(size); arr.append(m) }
        }
        return arr
    }

    private func fileSize(atPath path: String) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func directorySize(atPath path: String) -> UInt64 {
        let fm = FileManager.default
        let enumerator = fm.enumerator(atPath: path)
        var total: UInt64 = 0
        while let sub = enumerator?.nextObject() as? String {
            let full = URL(fileURLWithPath: path).appendingPathComponent(sub).path
            if let attrs = try? fm.attributesOfItem(atPath: full), (attrs[.type] as? FileAttributeType) == .typeRegular {
                total &+= (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            }
        }
        return total
    }

    /// 对二进制集合应用正则与过滤开关并累计大小（互斥：正则非空时不应用类型过滤）
    private func analyze(_ symbols: [SymbolModel], searchKey: String) -> UInt {
        var totalSize: UInt = 0
        let ignoreA = model.ignoreAOn
        let ignoreO = model.ignoreOOn
        let ignoreTbd = model.ignoreTbdOn
        let ignoreDylib = model.ignoreDylibOn
        let ignoreSpace = model.ignoreSpacePrefixOn
        func shouldIgnore(_ file: String) -> Bool {
            return (ignoreA && file.hasSuffix(".a"))
                || (ignoreO && file.hasSuffix(".o"))
                || (ignoreTbd && file.hasSuffix(".tbd"))
                || (ignoreDylib && file.hasSuffix(".dylib"))
                || (ignoreSpace && file.hasPrefix(" "))
        }
        for symbol in symbols {
            if !searchKey.isEmpty {
                let name = URL(fileURLWithPath: symbol.file).lastPathComponent
                if matches(name: name, searchKey: searchKey) {
                    append(symbol, ignore: false)
                    totalSize &+= symbol.size
                }
            } else {
                if shouldIgnore(symbol.file) {
                    append(symbol, ignore: true)
                } else {
                    append(symbol, ignore: false)
                    totalSize &+= symbol.size
                }
            }
        }
        return totalSize
    }

    /// 对资源集合应用正则并累计大小
    private func analyzeAssets(_ symbols: [SymbolModel], searchKey: String) -> UInt {
        var totalSize: UInt = 0
        for symbol in symbols {
            let name = URL(fileURLWithPath: symbol.file).lastPathComponent
            if !searchKey.isEmpty {
                if matches(name: name, searchKey: searchKey) { append(symbol, ignore: false); totalSize &+= symbol.size }
            } else { append(symbol, ignore: false); totalSize &+= symbol.size }
        }
        return totalSize
    }

    /// 将多关键字（以 + 连接）转换为并列正则表达式
    private func regex(from searchKey: String) -> String? {
        let key = searchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let parts = key.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return "(?:" + parts.joined(separator: "|") + ")"
    }

    /// 名称匹配：优先使用正则；否则使用大小写不敏感子串匹配
    private func matches(name: String, searchKey: String) -> Bool {
        if let pattern = regex(from: searchKey), !pattern.isEmpty {
            let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let r = NSRange(location: 0, length: name.count)
            return re?.firstMatch(in: name, options: [], range: r) != nil
        } else {
            return name.range(of: searchKey, options: .caseInsensitive) != nil
        }
    }

    /// 追加一行结果文本；忽略项使用浅灰色以做区分
    private func append(_ model: SymbolModel, ignore: Bool) {
        let sizeText: String
        if Double(model.size) / 1024.0 / 1024.0 > 1.0 {
            sizeText = String(format: "%.2fMiB", Double(model.size) / 1024.0 / 1024.0)
        } else {
            sizeText = String(format: "%.2fKiB", Double(model.size) / 1024.0)
        }
        let text = "\(sizeText)\t\t\(URL(fileURLWithPath: model.file).lastPathComponent)\r\n"
        if ignore {
            currentResult.append(NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.lightGray]))
        } else {
            currentResult.append(NSAttributedString(string: text))
        }
    }

    /// 基础格式校验：必须包含 # Object files、# Symbols 与 # Path 段
    private func checkContent(_ content: String) -> Bool {
        let objsRange = content.range(of: "# Object files:")
        guard objsRange != nil else { return false }
        let sub = String(content[objsRange!.upperBound...])
        let symbolsRange = sub.range(of: "# Symbols:")
        guard content.range(of: "# Path:") != nil, objsRange != nil, symbolsRange != nil else { return false }
        return true
    }

    /// 持久化规则与历史；UserDefaults 写入在后台，模型发布改用主线程
    private func persistRules(binaryRule: String, assetsRule: String) {
        let ud = UserDefaults.standard
        ud.set(binaryRule, forKey: "LM_BinaryRule")
        ud.set(assetsRule, forKey: "LM_AssetsRule")
        ud.set(model.syncRuleOn, forKey: "LM_SyncRuleOn")
        ud.set(model.ignoreEmbeddedOn, forKey: "LM_IgnoreEmbedded")
        ud.set(model.ignoreBundleOn, forKey: "LM_IgnoreBundle")
        ud.set(model.ignoreAOn, forKey: "LM_IgnoreA")
        ud.set(model.ignoreOOn, forKey: "LM_IgnoreO")
        ud.set(model.ignoreTbdOn, forKey: "LM_IgnoreTbd")
        ud.set(model.ignoreDylibOn, forKey: "LM_IgnoreDylib")
        ud.set(model.ignoreSpacePrefixOn, forKey: "LM_IgnoreSpacePrefix")
        var oldBR = (ud.array(forKey: "LM_BinaryRuleHistory") as? [String]) ?? []
        if !binaryRule.isEmpty {
            oldBR.removeAll { $0 == binaryRule }
            oldBR.insert(binaryRule, at: 0)
            if oldBR.count > 10 { oldBR.removeSubrange(10..<oldBR.count) }
            ud.set(oldBR, forKey: "LM_BinaryRuleHistory")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.model.binaryRuleHistory = oldBR
            }
        }
        var oldAR = (ud.array(forKey: "LM_AssetsRuleHistory") as? [String]) ?? []
        if !assetsRule.isEmpty {
            oldAR.removeAll { $0 == assetsRule }
            oldAR.insert(assetsRule, at: 0)
            if oldAR.count > 10 { oldAR.removeSubrange(10..<oldAR.count) }
            ud.set(oldAR, forKey: "LM_AssetsRuleHistory")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.model.assetsRuleHistory = oldAR
            }
        }
    }

    /// 追加三行汇总：总大小 / 二进制 / 资源（同时输出 MiB/KiB 与 1000 制口径）
    private func appendTotals(binaryTotal: UInt, bundleTotal: UInt, totalSize: UInt) {
        let text = String(format: "\r\n总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n(不包括忽略部分)\r\n",
                          Double(totalSize)/1024.0/1024.0, Double(totalSize)/1024.0, Double(totalSize)/1000.0/1000.0, Double(totalSize)/1000.0)
        currentResult.append(NSAttributedString(string: text))
        let binText = String(format: "二进制总大小: %.2fMiB(%.2fKiB)\r\n1000进制统计口径: %.2fMB(%.2fKB)\r\n",
                             Double(binaryTotal)/1024.0/1024.0, Double(binaryTotal)/1024.0, Double(binaryTotal)/1000.0/1000.0, Double(binaryTotal)/1000.0)
        currentResult.append(NSAttributedString(string: binText))
        let assetText = String(format: "资源文件: %.2fMiB(%.2fKiB)\r\n",
                              Double(bundleTotal)/1024.0/1024.0, Double(bundleTotal)/1024.0)
        currentResult.append(NSAttributedString(string: assetText))
    }

    /// 以模态弹窗提示错误或不合法输入
    private func showAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: NSApplication.shared.windows.first ?? NSWindow()) { _ in }
    }
}
