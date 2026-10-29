import Foundation

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }

    var shortName: String {
        switch self {
        case .en: return "EN"
        case .zhHans: return "中"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

enum L10n {
    static var language: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "packager.language"),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return .en
    }()

    static func string(_ key: String, language: AppLanguage) -> String {
        guard language == .zhHans else { return key }
        return zhHans[key] ?? key
    }

    static func s(_ key: String, _ language: AppLanguage, _ args: CVarArg...) -> String {
        let format = string(key, language: language)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: args)
    }

    /// Localized string in the active language.
    static func t(_ key: String) -> String {
        string(key, language: language)
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: args)
    }

    private static let zhHans: [String: String] = [
        // ── Chrome
        "Installer workbench": "安装包工作台",
        "Packages": "安装包",
        "Workspace": "工作区",
        "Settings": "设置",
        "Open Settings": "打开设置",
        "Local only · nothing uploaded": "仅本机运行 · 不上传文件",
        "Drop a .pkg or .mpkg\nanywhere in this window": "将 .pkg 或 .mpkg\n拖到窗口任意位置",
        "Drop to inspect": "松开以检查",
        "The package is unpacked in your workspace — nothing is installed.": "安装包将在工作区中解包，不会安装到系统。",
        "Packager": "Packager",

        // ── Welcome
        "Inspect, modernize, and repackage legacy macOS installers.": "检查、现代化并重新封装旧版 macOS 安装包。",
        "Unpacked in a private workspace, rebuilt as a clean XAR product.": "在私有工作区中解包，重新构建为干净的 XAR 产品。",
        "Drop an installer here": "将安装包拖到这里",
        "Flat .pkg · legacy .mpkg · bundle packages": "平面 .pkg · 旧式 .mpkg · Bundle 包",
        "Choose a package": "选择安装包",
        "Inspect": "检查",
        "Every component, script, and binary.": "每个组件、脚本与二进制。",
        "Modernize": "现代化",
        "Drop OS gates and relocatable flags.": "移除系统版本限制与可重定位标记。",
        "Repackage": "重新封装",
        "A fresh XAR product, saved locally.": "全新的 XAR 产品，保存在本地。",
        "Nothing is installed — everything happens inside your Packager workspace.": "不会安装任何内容——所有操作都在 Packager 工作区中完成。",
        "Repackaging…": "正在重新封装…",
        "Waiting for authorization": "等待授权",

        // ── Project
        "Structure": "结构",
        "Issues": "问题",
        "Inspecting": "正在检查",
        "Inspecting package": "正在检查安装包",
        "Unpacking into the workspace and walking every payload.": "正在工作区解包并遍历所有内容。",
        "Couldn’t inspect this package": "无法检查此安装包",
        "Try Again": "重试",
        "Reveal Workspace": "显示工作区",
        "Reveal Original": "显示原始安装包",
        "Reveal the original package": "在 Finder 中显示原始安装包",
        "Reveal the workspace": "在 Finder 中显示工作区",
        "Remove from Sidebar": "从侧栏移除",
        "Remove from sidebar": "从侧栏移除",
        "Reveal": "显示",
        "Reveal in Finder": "在 Finder 中显示",
        "Reveal Output in Finder": "在 Finder 中显示输出",
        "Reveal in Workspace": "在工作区中显示",
        "Clear Workspace": "清空工作区",
        "Clear": "清空",
        "Done": "完成",
        "Undo": "撤销",
        "Cancel": "取消",
        "Dismiss": "关闭",
        "Close": "关闭",
        "%d component(s)": "%d 个组件",
        "%d payload file(s)": "%d 个载荷文件",
        "%d component": "%d 个组件",
        "payload files": "个载荷文件",
        "components": "个组件",

        // ── Tree
        "Filter structure": "筛选结构",
        "All": "全部",
        "Binaries": "二进制",
        "Scripts": "脚本",
        "Warnings": "警告",
        "Expand All": "全部展开",
        "Collapse All": "全部折叠",
        "No items match this filter": "没有匹配的项目",
        "Clear Filter": "清除筛选",
        "legacy arch": "旧架构",
        "32-bit": "32 位",
        "high risk": "高风险",
        "review": "需复核",
        "Bill of materials": "文件清单（Bom）",
        "Symbolic link": "符号链接",
        "Component": "组件",
        "Install scripts": "安装脚本",
        "Distribution": "Distribution",
        "Payload": "Payload",
        "PackageInfo": "PackageInfo",
        "Resources": "Resources",
        "Os constraints": "系统限制",
        "%d more items": "还有 %d 项",
        "%d OS constraint(s)": "%d 个系统限制",
        "%d install script(s)": "%d 个安装脚本",
        "gzip archive": "gzip 归档",
        "bzip2 archive": "bzip2 归档",
        "xz archive": "xz 归档",
        "zstd archive": "zstd 归档",
        "raw archive": "原始归档",
        "More": "更多",

        // ── Issues
        "Review before repackaging": "重新封装前请复核",
        "Modernization fixes are applied to a copy in your workspace.": "现代化修改将应用于工作区中的副本。",
        "No findings": "未发现问题",
        "This package has no legacy gates or risky scripts. It can be repackaged as-is.": "此安装包没有旧版限制或高风险脚本，可直接重新封装。",
        "Critical": "严重",
        "Warning": "警告",
        "Note": "提示",
        "System version gate": "系统版本限制",
        "Legacy architecture declared": "声明了旧架构",
        "%d 32-bit binar(ies) found": "发现 %d 个 32 位二进制文件",
        "Relocatable components": "可重定位组件",
        "%d high-risk install script(s)": "%d 个高风险安装脚本",
        "%d install script(s) present": "%d 个安装脚本",
        "Signed package": "已签名安装包",
        "Payload not expanded": "载荷未展开",
        "Legacy bundle package": "旧式 Bundle 安装包",
        "Included in the next repackage": "将包含在下次重新封装中",
        "Remove version gate": "移除版本限制",
        "Clear relocatable": "清除可重定位",
        "Strip high-risk scripts": "剥离高风险脚本",
        "OS compatibility": "系统兼容性",
        "Architecture": "架构",
        "Relocation": "重定位",
        "Signature": "签名",
        "Integrity": "完整性",

        "Signed": "已签名",
        "Unsigned": "未签名",
        "The original package is not signed": "原始安装包未签名",
        "%@ declares %@": "%@ 声明了 %@",
        "%d binaries contain legacy slices": "发现 %d 个含旧架构切片的二进制文件",

        // ── Issue messages
        "The Distribution script gates installation on system version (%@).": "Distribution 脚本通过系统版本限制安装条件（%@）。",
        " A maximum bound will block installation on every newer macOS release.": " 上限设置会阻止在任何较新的 macOS 版本上安装。",
        " Installer JavaScript also inspects the host OS version.": " 安装器的 JavaScript 还会检查主机系统版本。",
        "Every detected executable contains only legacy architecture slices. Current macOS cannot run these executables.": "所有检测到的可执行文件都仅含旧架构切片，当前 macOS 无法运行这些程序。",
        "Some executable slices target i386, PowerPC, or 32-bit ARM. They cannot load on current macOS releases.": "部分可执行切片基于 i386、PowerPC 或 32 位 ARM，无法在当前 macOS 上加载。",
        "%d component(s) allow Installer to relocate the payload to another volume: %@.": "%d 个组件允许安装器将载荷重定位到其他卷：%@。",
        "%@ — %@. Stripping scripts changes install behavior; keep them if the package needs them.": "%@ — %@。剥离脚本会改变安装行为；如果安装包需要这些脚本，请保留。",
        "No dangerous commands were detected, but install scripts still run as root at install time.": "未检测到危险命令，但安装脚本在安装时仍以 root 权限运行。",
        "Status: %@. Repackaging rewrites the archive, so the existing signature will not carry over to the new product.": "状态：%@。重新封装会重写归档，现有签名不会转移到新产品。",
        "The payload could not be expanded in the workspace, so binary architecture checks are limited to declared metadata.": "无法在工作区展开载荷，因此二进制架构检查仅依据已声明的元数据。",
        "Bundle-style packages are rebuilt into a flat XAR archive for modern macOS.": "旧式 Bundle 安装包将被重新构建为适用于现代 macOS 的平面 XAR 归档。",
        "Deletes absolute system paths": "删除系统绝对路径",
        "Recursive deletion": "递归删除",
        "Disables Gatekeeper": "禁用 Gatekeeper",
        "Touches System Integrity Protection": "修改系统完整性保护（SIP）",
        "Loads kernel extensions": "加载内核扩展",
        "Writes inside /System": "写入 /System",
        "Pipes remote content into a shell": "将远程内容管道到 shell",
        "Downloads from the network": "从网络下载内容",
        "Escalates privileges": "提升权限",
        "Manages launchd services": "管理 launchd 服务",
        "Installs a persistent daemon": "安装常驻守护进程",
        "Modifies preferences": "修改偏好设置",
        "Makes files world-writable": "将文件设为全局可写",
        "Writes firmware variables": "写入固件变量",
        "Forgets receipt data": "清除安装回执",
        "Checks the host OS version": "检查主机系统版本",
        "Binary or encoded script": "二进制或编码后的脚本",
        "Windows inside /System": "写入 /System",

        // ── Rail
        "Edits are applied to a copy during repackaging.": "修改将在重新封装时应用于副本。",
        "Remove OS version limits": "移除系统版本限制",
        "Clear relocatable flags": "清除可重定位标记",
        "%d gate(s) in Distribution": "Distribution 中有 %d 个限制",
        "No version gates detected": "未检测到版本限制",
        "%d component(s) can relocate": "%d 个组件可重定位",
        "No relocatable components": "没有可重定位组件",
        "%d script(s) with risky commands": "含风险命令的脚本：%d 个",
        "No high-risk scripts": "没有高风险脚本",
        "%d selected": "已启用 %d 项",
        "selected": "已选择",
        "Output": "输出",
        "Choose the output folder": "选择输出文件夹",
        "Save to": "保存到",
        "Package name": "安装包名称",
        "Signature is not preserved on rebuild": "重新封装后签名将失效",
        "Saves %@ to %@": "将 %@ 保存到 %@",
        "Saving…": "正在保存…",
        "Activity": "活动",
        "No activity yet": "暂无活动",
        "%d events": "%d 条",
        "Show": "显示",
        "Hide": "隐藏",
        "Waiting for activity…": "等待活动…",
        "Local pkgutil pipeline · workspace only": "本机 pkgutil 流程 · 仅工作区",
        "Repackaging": "正在重新封装",
        "Administrator access": "需要管理员权限",
        "macOS will ask for your password. Packager runs only the command below.": "macOS 将要求输入密码。Packager 只会执行下方命令。",
        "Authorize…": "授权…",
        "Show command": "显示命令",
        "Hide command": "隐藏命令",
        "Package rebuilt": "安装包已重新封装",
        "Verified": "已验证",
        "%d fixes": "%d 项修复",
        "Repackage failed": "重新封装失败",

        // ── Settings
        "Interface language": "界面语言",
        "Changes apply immediately.": "切换后立即生效。",
        "Interface size": "界面尺寸",
        "Choose a window preset. You can also resize the window freely.": "选择窗口预设，也可以自由拖动窗口边缘调整大小。",
        "Compact": "紧凑",
        "Standard": "标准",
        "Large": "大",
        "Appearance": "外观",
        "System": "跟随系统",
        "Light": "浅色",
        "Dark": "深色",
        "Welcome screen": "欢迎界面",
        "Show the welcome screen again": "重新显示欢迎界面",
        "All unpacking happens here. The workspace is cleared when Packager quits.": "所有解包都在这里进行，退出 Packager 时会清空工作区。",
        "About": "关于",
        "Version %@": "版本 %@",
        "MIT License": "MIT 许可证",
        "Show welcome again": "重新显示欢迎界面",
        "Language": "语言",
        "Open the folder": "打开文件夹",
        "Built with pkgutil, pkgbuild, and productbuild.": "由 pkgutil、pkgbuild 与 productbuild 驱动。",
        "Packager is a local installer workbench. Nothing is uploaded.": "Packager 是本地安装包工作台，不会上传任何内容。",

        // ── Onboarding
        "Choose your language": "选择你的语言",
        "选择你的语言": "选择你的语言",
        "Packager will use this language across the app. You can change it later in Settings.": "Packager 将使用此语言显示界面，之后可在设置中修改。",
        "Continue in English": "Continue in English",
        "使用中文界面": "使用中文界面",
        "You can change language, interface size, and appearance later in Settings.": "之后可在设置中修改语言、界面尺寸与外观。",
        "A local workbench for legacy macOS installers.": "旧版 macOS 安装包的本地工作台。",
        "Inspect · Modernize · Repackage": "检查 · 现代化 · 重新封装",
        "Packager can’t write to %@. Authorize once to save the new package there.": "Packager 无法写入 %@。请授权一次以保存新的安装包。",
        "Saving to %@ requires administrator access.": "保存到 %@ 需要管理员权限。",

        // ── Commands
        "Open Package…": "打开安装包…",
        "Settings…": "设置…",

        // ── Alerts
        "Packager works with .pkg and .mpkg installers. “%@” is not an installer package.": "Packager 仅支持 .pkg 与 .mpkg 安装包。“%@” 不是安装包。",
        "That item no longer exists on disk.": "该项目已不在磁盘上。",
        "Those items weren’t readable as files. Drop a .pkg or .mpkg instead.": "无法读取这些项目。请改为拖入 .pkg 或 .mpkg。",
        "OK": "好",

        // ── Logs
        "Preparing the workspace": "正在准备工作区",
        "Waiting for macOS authorization": "等待 macOS 授权",
        "Choose": "选择",
        "Choose where Packager should save the rebuilt installer.": "选择重新封装后的安装包保存位置。",
        "Choose a .pkg or .mpkg installer to inspect in the workspace.": "选择一个 .pkg 或 .mpkg 安装包，在工作区中检查。",
        "Canceling the current operation": "正在取消当前操作",
        "Reading %@": "正在读取 %@",
        "Workspace: %@": "工作区：%@",
        "Bundle package detected": "检测到 Bundle 安装包",
        "Flat package detected": "检测到平面安装包",
        "Copying bundle into the workspace": "正在将 Bundle 复制到工作区",
        "Expanding archive into the workspace": "正在将归档展开到工作区",
        "Expanding payloads for binary inspection": "正在展开载荷以检查二进制",
        "Trying component-wise payload expansion": "正在逐个展开组件载荷",
        "Payload expansion unavailable — structure only": "载荷无法展开——仅显示结构",
        "Found %d system version constraint(s)": "发现 %d 个系统版本限制",
        "Parsed %@": "已解析 %@",
        "Could not expand payload for %@": "无法展开 %@ 的载荷",
        "Could not rewrite Distribution as XML: %@": "无法将 Distribution 重写为 XML：%@",
        "Inspection complete · %d components · %d payload files · %d legacy binaries": "检查完成 · %d 个组件 · %d 个载荷文件 · %d 个旧架构二进制",
        "Ready · %d components · %d binaries · %d payload files": "就绪 · %d 个组件 · %d 个二进制 · %d 个载荷文件",
        "%d legacy architecture slices detected": "检测到 %d 个旧架构切片",
        "Payload expansion was not available — binary detection is limited": "载荷无法展开——二进制检测受限",
        "Repackage requested": "已请求重新封装",
        "Option · remove OS version limits": "选项 · 移除系统版本限制",
        "Option · clear relocatable flags": "选项 · 清除可重定位标记",
        "Option · strip high-risk scripts": "选项 · 剥离高风险脚本",
        "Saved %@ · %@ · %@": "已保存 %@ · %@ · %@",
        "Saved %@": "已保存 %@",
        "Requesting administrator authorization": "正在请求管理员授权",
        "Canceled": "已取消",
        "Repackage canceled": "已取消重新封装",
        "Cancel the current operation": "取消当前操作",
        "Output folder set to %@": "输出文件夹已设置为 %@",
        "Workspace cleared": "工作区已清空",
        "Re-expanding the original package in the workspace": "正在工作区重新展开原始安装包",
        "Workspace expansion ready (%@)": "工作区展开完成（%@）",
        "Removed %d system version constraint(s)": "已移除 %d 个系统版本限制",
        "Distribution has no removable version constraints": "Distribution 中没有可移除的版本限制",
        "No Distribution script in this package": "此安装包没有 Distribution 脚本",
        "Stripped script %@ from %@": "已从 %@ 剥离脚本 %@",
        "Cleared relocatable on %@": "已清除 %@ 的可重定位标记",
        "Repackaging as a flat XAR archive": "正在重新封装为平面 XAR 归档",
        "Wrote %@ (%@)": "已写入 %@（%@）",
        "Verifying the new archive": "正在校验新归档",
        "Archive verified": "归档校验通过",
        "Authorized · saved %@": "授权成功 · 已保存 %@",
        "No pipeline available": "没有可用的处理流程",
        "Authorization was canceled.": "授权已取消。",
        "Authorization failed.": "授权失败。",
        "The package no longer exists at that location.": "安装包已不在该位置。",
        "The package could not be expanded.": "无法展开此安装包。",
        "No installable components were found inside this package.": "此安装包中没有可安装的组件。",
        "Operation canceled.": "操作已取消。",

        // ── Misc
        "No items": "没有项目",
        "Filter": "筛选",
        "Selected": "已选择",
        "component": "组件",
        "payload": "载荷",
        "signature": "签名",
        "Bundle": "Bundle",
        "Flat XAR": "平面 XAR",
    ]
}

func T(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.t(key)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: L10n.language.locale, arguments: args)
}

/// Turns English "(s)" markers into a proper plural using the first number in the text.
func P(_ text: String) -> String {
    guard L10n.language == .en, text.contains("(s)") else { return text }
    let number = text.split(whereSeparator: { $0 == " " || $0 == "·" })
        .compactMap { Int($0) }
        .first ?? 0
    return text.replacingOccurrences(of: "(s)", with: number == 1 ? "" : "s")
}

func TP(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
    let format = L10n.t(key, count, args)
    return P(format)
}
