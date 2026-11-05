import AppKit
import SwiftUI
import TokenPetAssets

/// Connecting Claude Code's status line to the pet: the bridge script next to limits.json, and the
/// settings.json snippet. ClaudeConnect writes that snippet in for you, after you see the change.
enum StatusLineSetup {
    /// The bridge script shipped in the .app, or the one in the source tree under `swift run`.
    static var bundledBridge: URL? {
        if let u = Bundle.main.url(forResource: "statusline-bridge", withExtension: "sh") { return u }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../bridge/statusline-bridge.sh").standardized
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }

    /// The command for settings.json. `dir` is where limits.json lives (the bridge writes there).
    static func command(dir: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let defaultDir = home.appendingPathComponent(".claude/token-pet").standardized.path
        if dir.standardized.path == defaultDir { return "sh ~/.claude/token-pet/statusline-bridge.sh" }
        let d = dir.standardized.path.replacingOccurrences(of: "'", with: "'\\''")
        return "TOKENPET_DIR='\(d)' sh '\(d)/statusline-bridge.sh'"
    }

    /// The text to paste inside the top-level object of ~/.claude/settings.json.
    static func snippet(command: String) -> String {
        let c = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"statusLine\": {\n  \"type\": \"command\",\n  \"command\": \"\(c)\"\n}"
    }

    /// A bridge installed earlier in `dir` that differs from this app's is replaced, so an update reaches
    /// it (this version pins hashed account ids to status-line sessions). Nothing happens where none was installed;
    /// settings.json is not touched.
    static func refreshInstalled(in dir: URL) {
        let dest = dir.appendingPathComponent("statusline-bridge.sh")
        guard let src = bundledBridge, let have = try? Data(contentsOf: dest), have != (try? Data(contentsOf: src)) else { return }
        install(into: dir)
    }

    /// Copies the bridge script into `dir` (made if missing). Returns false if there is no script to copy.
    @discardableResult static func install(into dir: URL) -> Bool {
        guard let src = bundledBridge else { return false }
        let fm = FileManager.default, dest = dir.appendingPathComponent("statusline-bridge.sh")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
            return true
        } catch {
            FileHandle.standardError.write("bridge install: \(error)\n".data(using: .utf8)!)
            return false
        }
    }
}

/// First-run guide, about 30 seconds: what Grandpa shows, connecting Claude Code, where Settings are. Skippable.
struct OnboardingView: View {
    @ObservedObject var model: UsageModel
    var done: () -> Void
    @State var page = 0
    @State private var copied = false
    @State private var linked = ClaudeConnect.State.notConnected
    @State private var connectNote: String?

    private var dir: URL { model.bridgeURL.deletingLastPathComponent() }
    private var snippet: String { StatusLineSetup.snippet(command: StatusLineSetup.command(dir: dir, home: home)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                switch page {
                case 0: story
                case 1: connect
                default: places
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in Circle().fill(Color.primary.opacity(i == page ? 0.7 : 0.18)).frame(width: 6, height: 6) }
                }
                Spacer()
                if page < 2 { Button(L.t("Skip", "건너뛰기", "スキップ", "跳过")) { done() } }
                if page > 0 { Button(L.t("Back", "이전", "戻る", "上一步")) { page -= 1 } }
                if page < 2 {
                    Button(L.t("Next", "다음", "次へ", "下一步")) { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L.t("Start digging", "시작하기", "掘りはじめる", "开始挖山")) { done() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 460, height: 520)
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: Yugong.scene(SceneInfo(state: .lively, carrier: 0.5, mountainLeft: 0.7, grandson: 0.3, night: false),
                                                     t: 0, size: PopoverView.sceneSize))
                .interpolation(.none)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity)
            Text(L.t("Meet Grandpa Yugong", "우공 할아버지를 소개해요", "愚公じいさんを紹介します", "认识一下愚公爷爷")).font(.title2.bold())
            Text(L.t("In the old tale he moved a mountain one shovelful at a time. Now he lives in your menu bar and digs with your Claude Code tokens.",
                     "옛이야기 속 우공은 산을 한 삽씩 옮겼어요. 이제 메뉴바에 살면서 Claude Code 토큰으로 삽질해요.",
                     "昔話の愚公は、山をひとすくいずつ移しました。今はメニューバーに住み、Claude Code のトークンで掘っています。",
                     "寓言里的愚公一锹一锹地移山。如今他住在菜单栏里，用你的 Claude Code token 挖土。"))
                .fixedSize(horizontal: false, vertical: true)
            row(figure(.straining, carrier: 0.8), L.t("The carrier", "지게", "背負子", "背架"),
                L.t("Your 5-hour limit. Full: he naps until the reset.", "5시간 한도예요. 가득 차면 리셋까지 쉬어요.",
                    "5時間リミットです。いっぱいになるとリセットまで昼寝します。", "你的 5 小时额度。装满后他会打盹到重置。"))
            row(figure(.lively, carrier: 0.3), L.t("His pace", "삽질 속도", "掘る速さ", "挖土速度"),
                L.t("Fast when tokens flow, sweating when you head for the limit.", "토큰이 빨리 나오면 빨리 파고, 한도에 닿을 속도면 땀을 흘려요.",
                    "トークンが速く流れると速く掘り、リミットに向かうと汗をかきます。", "token 来得快他就挖得快，快到额度时会流汗。"))
            row(Image(systemName: "mountain.2.fill").font(.system(size: 24)).foregroundColor(Color(red: 0.36, green: 0.55, blue: 0.4)),
                L.t("The mountain", "산", "山", "大山"),
                L.t("Every token you have used, counted on this Mac only.", "지금까지 쓴 모든 토큰이에요. 이 Mac에서만 세요.",
                    "これまで使ったすべてのトークン。この Mac の中だけで数えます。", "你用过的所有 token，只在这台 Mac 上统计。"))
        }
    }

    /// Where things are, so nobody has to hunt for Settings.
    private var places: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Where things are", "어디에 뭐가 있나요", "どこに何があるか", "功能都在哪里")).font(.title2.bold())
            row(figure(.lively, carrier: 0.5), L.t("Click Grandpa in the menu bar", "메뉴바의 할아버지를 누르면", "メニューバーのおじいさんをクリック", "点击菜单栏里的爷爷"),
                L.t("The scene and your numbers. ⌄ shows more: title, sources, account.", "장면과 숫자가 나와요. ⌄를 누르면 칭호·출처·계정을 더 보여 줘요.",
                    "場面と数字が出ます。⌄ で称号・出どころ・アカウントも見られます。", "显示场景和数字。点 ⌄ 还能看称号、来源、账号。"))
            row(Image(systemName: "gearshape").font(.system(size: 24)).foregroundColor(.secondary), L.t("Settings", "설정", "設定", "设置"),
                L.t("The gear in that popover: language, the menu bar number, the family watching other AIs, notifications. “How it works and Claude Code setup…” brings this guide back.",
                    "그 창의 톱니바퀴예요. 언어, 메뉴바 숫자, 다른 AI를 맡는 식구, 알림을 바꿔요. ‘사용법과 Claude Code 연결…’을 누르면 이 안내가 다시 나와요.",
                    "そのポップオーバーの歯車です。言語、メニューバーの数字、ほかの AI を受け持つ家族、通知を変えられます。「使い方と Claude Code の接続…」でこの案内がまた開きます。",
                    "就是弹出窗口里的齿轮：语言、菜单栏数字、看管其他 AI 的家人、通知。点“使用说明与 Claude Code 连接…”可以再次打开本指南。"))
            row(Image(systemName: "macwindow").font(.system(size: 24)).foregroundColor(.secondary), L.t("Window", "창으로 보기", "ウィンドウ", "窗口"),
                L.t("Keeps him on your desktop. Its ⋯ menu sets the size, a compact scene-only view, and always on top.",
                    "바탕화면에 계속 띄워 둬요. ⋯ 메뉴에서 크기, 장면만 보는 간단히 보기, 항상 위를 골라요.",
                    "デスクトップに出しておけます。⋯ メニューで大きさ、場面だけのコンパクト表示、常に手前を選べます。",
                    "把他一直留在桌面上。⋯ 菜单可以设大小、只看场景的精简视图、始终置顶。"))
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Connect Claude Code", "Claude Code 연결", "Claude Code と接続", "连接 Claude Code")).font(.title2.bold())
            Text(L.t("Claude Code tells its status line your official limits. “Connect” adds this to ~/.claude/settings.json after showing you the change, with a backup; or paste it into the top level yourself:",
                     "Claude Code는 상태줄에 공식 한도를 알려 줘요. ‘연결하기’를 누르면 바뀔 내용을 보여 준 뒤 백업하고 ~/.claude/settings.json에 넣어요. 직접 맨 바깥 객체에 붙여 넣어도 돼요:",
                     "Claude Code はステータスラインに公式のリミットを渡します。「接続」を押すと、変更内容を見せてからバックアップを取り ~/.claude/settings.json に追加します。自分で一番外側のオブジェクトに貼ってもかまいません：",
                     "Claude Code 会把你的官方额度告诉它的状态栏。点“连接”会先给你看改动，备份后再加到 ~/.claude/settings.json；也可以自己粘贴到最外层对象中："))
                .fixedSize(horizontal: false, vertical: true)
            Text(snippet)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
            HStack {
                if linked == .connected || linked == .chained {
                    Button(L.t("Undo", "되돌리기", "元に戻す", "撤销")) { disconnectClaude() }
                } else if linked == .notConnected {
                    Button(L.t("Connect", "연결하기", "接続", "连接")) { connectClaude() }.buttonStyle(.borderedProminent)
                }
                Button {
                    StatusLineSetup.install(into: dir)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    copied = true
                } label: { Label(copied ? L.t("Copied",
                                              "복사했어요",
                                              "コピーしました",
                                              "已复制") : L.t("Copy snippet",
                                                                                         "스니펫 복사",
                                                                                         "スニペットをコピー",
                                                                                         "复制代码片段"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                Spacer()
                status
            }
            Text(L.t("Copying also puts the small bridge script in \(dir.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")). It keeps only the rate_limits numbers: no prompts, no paths, no network.",
                     "복사하면 작은 브리지 스크립트도 \(dir.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))에 넣어요. 한도 숫자(rate_limits)만 저장하고 프롬프트·경로는 남기지 않으며 네트워크도 쓰지 않아요.",
                     "コピーすると小さなブリッジスクリプトも \(dir.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")) に置きます。保存するのは rate_limits の数値だけで、プロンプトやパスは残さず、ネットワークも使いません。",
                     "复制时也会把一个小小的桥接脚本放到 \(dir.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))。它只保存 rate_limits 数值：不存提示词、不存路径、不联网。"))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(connectNote ?? L.t("Already have a status line? “Connect” keeps it: the bridge passes it the same input and shows what it prints. “Undo” puts it back as it was.",
                     "이미 상태줄을 쓰고 있어도 ‘연결하기’는 그대로 살려 둬요. 브리지가 같은 입력을 넘기고 그 출력을 보여 줘요. ‘되돌리기’를 누르면 원래대로 돌아가요.",
                     "すでにステータスラインがあっても「接続」はそのまま残します。ブリッジが同じ入力を渡し、その出力を表示します。「元に戻す」で元どおりになります。",
                     "已经有状态栏了？“连接”会保留它：桥接脚本把同样的输入交给它，并显示它的输出。“撤销”会把它恢复原样。"))
                .font(.caption).foregroundColor(connectNote == nil ? .secondary : .primary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(L.t("The numbers arrive after Claude Code's next reply. Until then Grandpa honestly says he doesn't know.",
                     "숫자는 Claude Code가 다음에 답할 때 들어와요. 그 전까지 할아버지는 솔직하게 모른다고 해요.",
                     "数値は Claude Code が次に返答したときに届きます。それまでおじいさんは正直に「わからない」と言います。",
                     "数字会在 Claude Code 下次回复后到来。在那之前，爷爷会老实地说不知道。"))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { linked = ClaudeConnect.state(home: home, dir: dir) }
    }

    /// Shows the statusLine before and after, and writes only when the user says so.
    private func connectClaude() {
        do {
            let c = try ClaudeConnect.connect(home: home, dir: dir)   // first: it checks ~/.claude, which installing would make
            guard StatusLineSetup.install(into: dir) else { throw ClaudeConnect.Problem.noBridge }
            guard let c else { return linked = ClaudeConnect.state(home: home, dir: dir) }
            let a = NSAlert()
            a.messageText = L.t("Change ~/.claude/settings.json?", "~/.claude/settings.json을 바꿀까요?", "~/.claude/settings.json を変更しますか？", "要修改 ~/.claude/settings.json 吗？")
            a.informativeText = "statusLine " + L.t("before", "지금", "変更前", "修改前") + ":\n\(c.before ?? "-")\n\nstatusLine " + L.t("after", "바뀐 뒤", "変更後", "修改后") + ":\n\(c.after ?? "-")\n\n"
                + L.t("Everything else stays as it is. A backup goes to \(dir.path).",
                      "나머지는 그대로예요. 백업은 \(dir.path)에 남겨요.",
                      "ほかの設定はそのままです。バックアップは \(dir.path) に保存します。",
                      "其他设置保持不变。备份保存在 \(dir.path)。")
            a.addButton(withTitle: L.t("Connect", "연결하기", "接続", "连接"))
            a.addButton(withTitle: L.t("Cancel", "취소", "キャンセル", "取消"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
            let backup = try ClaudeConnect.apply(c, backupDir: dir)
            connectNote = L.t("Connected. Backup: \(backup?.lastPathComponent ?? "-")", "연결했어요. 백업: \(backup?.lastPathComponent ?? "-")",
                              "接続しました。バックアップ：\(backup?.lastPathComponent ?? "-")", "已连接。备份：\(backup?.lastPathComponent ?? "-")")
        } catch let p as ClaudeConnect.Problem {
            connectNote = p.message
        } catch {
            connectNote = error.localizedDescription
        }
        linked = ClaudeConnect.state(home: home, dir: dir)
    }

    private func disconnectClaude() {
        do {
            if let c = try ClaudeConnect.disconnect(home: home, dir: dir) { try ClaudeConnect.apply(c, backupDir: dir) }
            connectNote = L.t("Disconnected: your status line is as it was.", "되돌렸어요. 상태줄이 원래대로예요.", "元に戻しました。ステータスラインは元どおりです。", "已撤销，状态栏恢复原样。")
        } catch let p as ClaudeConnect.Problem {
            connectNote = p.message
        } catch {
            connectNote = error.localizedDescription
        }
        linked = ClaudeConnect.state(home: home, dir: dir)
    }

    @ViewBuilder private var status: some View {
        if model.snap.known && !model.snap.demo {
            Label(L.t("Connected",
                      "연결됨",
                      "接続済み",
                      "已连接") + (model.snap.captured.map { " · \(Fmt.clock($0))" } ?? ""), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green).font(.callout)
        } else {
            HStack(spacing: 6) {
                Text(L.t("Waiting for the first reading",
                         "첫 값을 기다리는 중",
                         "最初の値を待っています",
                         "正在等待第一个读数")).font(.callout).foregroundColor(.secondary)
                Button(L.t("Check", "확인", "確認", "检查")) { model.refresh() }.disabled(model.scanning)
            }
        }
    }

    private func figure(_ st: PetState, carrier: Double) -> some View {
        // the same 20-pixel sprite as in the menu bar, enlarged
        Image(nsImage: Yugong.image(st, t: 0.2, size: 20, menuBar: true, carrier: carrier))
            .resizable().interpolation(.none).frame(width: 40, height: 40)
    }

    private func row(_ icon: some View, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
