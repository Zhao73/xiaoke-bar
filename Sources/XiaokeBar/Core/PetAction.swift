import Foundation

/// 宠物在做的动作（按会话里最后一次调用的工具来定）
enum PetAction: String, Codable, CaseIterable {
    // 工作中
    case idle, thinking, typing, reading, searching, running, building, planning, asking, delegating
    case photo, git, network, deploy, install
    // 自娱自乐 / 互动
    case guitar, dance, coffee, sleep, celebrate, worried, wave, stretch, juggle, skate, spin, love, dangle
    // 乐队
    case piano, bass, drums, flute, violin, erhu, musicbox
    // 心情和互动
    case whipped, eat, laugh, sulk, angry, walkDog, fetch, catNap

    var label: String {
        switch self {
        case .idle: return L("发呆")
        case .thinking: return L("思考中")
        case .typing: return L("改代码")
        case .reading: return L("看文件")
        case .searching: return L("搜索中")
        case .running: return L("跑命令")
        case .delegating: return L("派小弟干活")
        case .guitar: return L("弹吉他")
        case .dance: return L("跳舞")
        case .coffee: return L("喝咖啡")
        case .sleep: return L("睡觉")
        case .celebrate: return L("庆祝")
        case .worried: return L("有点慌")
        case .building: return L("编译测试")
        case .photo: return L("截图")
        case .git: return L("管代码版本")
        case .network: return L("联网查询")
        case .deploy: return L("部署上线")
        case .install: return L("装依赖")
        case .planning: return L("排计划")
        case .asking: return L("等你回复")
        case .wave: return L("打招呼")
        case .stretch: return L("伸懒腰")
        case .juggle: return L("抛球")
        case .skate: return L("玩滑板")
        case .spin: return L("转圈圈")
        case .love: return L("被摸头")
        case .dangle: return L("被拎起来")
        case .piano: return L("弹钢琴")
        case .bass: return L("弹贝斯")
        case .drums: return L("打鼓")
        case .flute: return L("吹长笛")
        case .violin: return L("拉小提琴")
        case .erhu: return L("拉二胡")
        case .musicbox: return L("摇八音盒")
        case .whipped: return L("挨了一鞭")
        case .eat: return L("吃零食")
        case .laugh: return L("笑得打滚")
        case .sulk: return L("闹情绪")
        case .angry: return L("生气了")
        case .walkDog: return L("遛狗")
        case .fetch: return L("和狗狗玩球")
        case .catNap: return L("陪猫睡觉")
        }
    }

    /// 工具名 → 动作（Claude Code 的工具名和 Codex 的函数名都认）
    static func from(tool: String?, detail: String? = nil) -> PetAction {
        guard let t = tool?.lowercased() else { return .thinking }
        if t.hasPrefix("mcp__") { return .typing }
        switch t {
        case "bash", "exec_command", "shell", "local_shell", "write_stdin", "monitor", "run_terminal_cmd":
            return command(detail)
        case "todowrite", "taskcreate", "taskupdate", "tasklist", "update_plan", "enterplanmode", "exitplanmode", "write_todos": return .planning
        case "askuserquestion", "request_user_input", "ask_user": return .asking
        case "edit", "write", "multiedit", "notebookedit", "apply_patch", "replace", "write_file": return .typing
        case "read", "view_image", "read_file", "read_many_files": return .reading
        case "grep", "glob", "websearch", "webfetch", "web_search", "toolsearch", "google_web_search", "web_fetch", "search_file_content", "list_directory": return .searching
        case "agent", "task", "workflow", "sendmessage", "spawn_agent": return .delegating
        default: return .typing
        }
    }

    /// 按命令说明（或命令本身）细分：同样是跑终端，截图、提交代码、联网、部署、装依赖、编译各有各的动画
    static func command(_ detail: String?) -> PetAction {
        guard let d = detail?.lowercased() else { return .running }
        for (a, words) in commandRules where words.contains(where: { d.contains($0) }) { return a }
        return .running
    }

    /// 界面每次重画都会问一次宠物该做什么动作，关键词表只建一次
    private static let commandRules: [(PetAction, [String])] = [
        (.photo, ["screenshot", "screencapture", "capture", "snapshot", "截图", "截屏", "スクショ"]),
        (.git, ["git ", "commit", "branch", "merge", "rebase", "push", "pull request", "提交", "分支", "コミット"]),
        (.deploy, ["deploy", "ssh ", "publish", "release", "upload", "rsync", "wrangler", "vercel", "部署", "上线", "发布", "上传", "デプロイ"]),
        (.install, ["install", "brew ", "pip ", "npm i ", "pnpm add", "yarn add", "安装", "依赖", "インストール"]),
        (.building, ["build", "test", "compile", "xcodebuild", "cargo", "make", "gradle", "pytest", "lint", "typecheck", "打包", "编译", "构建", "测试", "ビルド", "テスト"]),
        (.network, ["curl", "fetch", "download", "http", "api", "request", "query", "查询", "下载", "请求", "联网"]),
    ]
}
