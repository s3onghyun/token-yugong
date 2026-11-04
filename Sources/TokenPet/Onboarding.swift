import AppKit
import SwiftUI
import TokenPetAssets

/// Connecting Claude Code's status line to the pet. The app never edits ~/.claude/settings.json:
/// it copies the bridge script next to limits.json and hands the user a snippet to paste.
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
    /// it (this version adds the hashed account). Nothing happens where none was installed; settings.json is not touched.
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

/// First-run guide: who Grandpa is, what each picture means, and how to connect Claude Code.
struct OnboardingView: View {
    @ObservedObject var model: UsageModel
    var done: () -> Void
    @State var page = 0
    @State private var copied = false

    private var dir: URL { model.bridgeURL.deletingLastPathComponent() }
    private var snippet: String { StatusLineSetup.snippet(command: StatusLineSetup.command(dir: dir)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                switch page {
                case 0: story
                case 1: legend
                default: connect
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in Circle().fill(Color.primary.opacity(i == page ? 0.7 : 0.18)).frame(width: 6, height: 6) }
                }
                Spacer()
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
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: Yugong.scene(SceneInfo(state: .lively, carrier: 0.5, mountainLeft: 0.7, grandson: 0.3, night: false),
                                                     t: 0, size: PopoverView.sceneSize))
                .interpolation(.none)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity)
            Text(L.t("Meet Grandpa Yugong", "우공 할아버지를 소개해요", "愚公じいさんを紹介します", "认识一下愚公爷爷")).font(.title2.bold())
            Text(L.t("In an old Chinese tale, Yugong was ninety when he decided to move the mountains in front of his house, one shovel at a time. People laughed. He said: “When I am gone my sons will dig, then their sons. The mountain does not grow.” Heaven was so moved that it carried the mountains away.",
                     "옛이야기 속 우공은 아흔 살에 집 앞을 막은 산을 옮기기로 했어요. 한 삽씩요. 사람들이 비웃자 “내가 못 하면 아들이, 손자가 하면 되지. 산은 더 자라지 않으니까”라고 했죠. 그 끈기에 하늘이 감동해 산을 옮겨 주었답니다.",
                     "中国の昔話で、愚公は九十歳のとき、家の前をふさぐ山をひとすくいずつ移そうと決めました。人々は笑いましたが、愚公は言いました。「わしが死んでも息子が掘り、その子らが掘る。山はこれ以上大きくならん」。その根気に天が心を打たれ、山を運び去ってくれたのです。",
                     "在中国古老的寓言里，愚公九十岁时决定一锹一锹地移走挡在家门前的大山。人们笑他，他说：“我死了还有儿子，儿子又有孙子，子子孙孙无穷尽，而山不会再长高。”天帝被他的毅力感动，派神把山搬走了。"))
                .fixedSize(horizontal: false, vertical: true)
            Text(L.t("Now he lives in your menu bar, and every token you use with Claude Code is one more shovelful.",
                     "이제 할아버지는 메뉴바에 살면서, Claude Code로 쓰는 토큰을 한 삽 한 삽 퍼 나릅니다.",
                     "今はあなたのメニューバーに住み、Claude Code で使うトークンをひとすくいずつ運んでいます。",
                     "如今他住在你的菜单栏里，你在 Claude Code 中用掉的每个 token 都是他又挖下的一锹土。"))
                .fixedSize(horizontal: false, vertical: true)
            Text(L.t("Click him in the menu bar to see this scene and your numbers. Its “Window” button keeps him on your desktop.",
                     "메뉴바의 할아버지를 눌러 보세요. 이 장면과 숫자가 나와요. ‘창으로 보기’를 누르면 바탕화면에 계속 띄워 둘 수 있어요.",
                     "メニューバーのおじいさんをクリックすると、この場面と数字が出ます。「ウィンドウ」ボタンでデスクトップに出しておけます。",
                     "点击菜单栏里的爷爷，就能看到这个场景和数字。点“窗口”按钮可以把他一直留在桌面上。"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("What you are looking at", "무엇을 보여 주나요", "見えているもの", "你看到的是什么")).font(.title2.bold())
            row(figure(.straining, carrier: 0.8), L.t("The carrier (지게)", "지게", "背負子（チゲ）", "背架（지게）"),
                L.t("Earth in his A-frame carrier is your main AI's 5-hour limit (Claude unless you pick another in Settings › Family). Full = he sits down and naps until it resets, and the menu bar shows when he starts again. Accounts with only a weekly limit fill it with the week; going past today's fair share (1/7 of the week) only makes him sweat.",
                    "등에 진 지게의 흙이 주로 쓰는 AI의 5시간 한도예요(기본 Claude, 설정 › 식구에서 바꿔요). 가득 차면 리셋까지 쉬고, 메뉴바에 다시 퍼는 시각이 나와요. 주간 한도만 있는 계정은 주간 한도만큼 차고, 오늘 몫(주간의 1/7)을 넘으면 땀만 흘려요.",
                    "背負子の土は、メインの AI の5時間リミットです（設定 › 家族で変えない限り Claude）。いっぱいになるとリセットまで座って昼寝し、メニューバーに再開の時刻が出ます。週間リミットだけのアカウントでは週の分で満ちていき、今日の取り分（週の1/7）を超えても汗をかくだけです。",
                    "背架上的土就是你主要 AI 的 5 小时额度（默认是 Claude，可在 设置 › 家人 中更改）。装满后他会坐下打盹直到重置，菜单栏会显示他何时重新开工。只有每周额度的账号按整周来装；超过今天的份额（每周的 1/7）只会让他流汗。"))
            row(figure(.lively, carrier: 0.3), L.t("His pace", "삽질 속도", "掘る速さ", "挖土速度"),
                L.t("He digs faster when tokens flow faster on this Mac, leans on his shovel when it is quiet, and strains when you are heading for the limit before the reset.",
                    "이 Mac에서 토큰이 빨리 나오면 빨리 파고, 조용하면 삽에 기대 쉬어요. 리셋 전에 한도에 닿을 속도면 힘에 부쳐 해요.",
                    "この Mac でトークンが速く流れると速く掘り、静かなときはシャベルにもたれて休み、リセット前にリミットに届きそうだと息が上がります。",
                    "这台 Mac 上 token 来得越快，他挖得越快；安静时就倚着铁锹歇着；照这个速度会在重置前用完额度时，他就累得直喘。"))
            row(Image(systemName: "mountain.2.fill").font(.system(size: 24)).foregroundColor(Color(red: 0.36, green: 0.55, blue: 0.4)),
                L.t("The mountain", "산", "山", "大山"),
                L.t("Every token you have ever used wears it down (counted from your local logs, kept on this Mac). Carry a whole mountain away and heaven takes notice.",
                    "지금까지 쓴 모든 토큰이 산을 깎아요(이 Mac의 로그로 세고, 이 Mac에만 저장). 산 하나를 다 옮기면 하늘이 감동해요.",
                    "これまで使ったすべてのトークンが山を削ります（この Mac のログから数え、この Mac にだけ保存）。山をひとつ運びきると、天が気づいてくれます。",
                    "你用过的每一个 token 都在削减大山（根据本机日志统计，只保存在这台 Mac 上）。搬走整座山，上天就会注意到。"))
            row(Image(systemName: "figure.2.and.child.holdinghands").font(.system(size: 22)).foregroundColor(.secondary),
                L.t("The family", "식구", "家族", "家人"),
                L.t("His son, his grandson and the neighbour's boy can each watch another AI (Codex, Gemini, the OpenAI or DeepSeek API) and carry its meter. What an AI does not report, they say they don't know.",
                    "아들, 손주, 이웃집 아이가 다른 AI(Codex, Gemini, OpenAI·DeepSeek API)를 하나씩 맡아 미터를 져요. AI가 알려 주지 않는 건 모른다고 해요.",
                    "息子、孫、隣の子がそれぞれ別の AI（Codex、Gemini、OpenAI や DeepSeek の API）を受け持ち、そのメーターを背負います。AI が教えてくれないことは「わからない」と言います。",
                    "儿子、孙子和邻家小孩可以各自看管另一个 AI（Codex、Gemini、OpenAI 或 DeepSeek API），背着它的额度表。AI 没有告诉的，他们就说不知道。"))
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Connect Claude Code", "Claude Code 연결", "Claude Code と接続", "连接 Claude Code")).font(.title2.bold())
            Text(L.t("Claude Code tells its status line your official limits. Add this to the top level of ~/.claude/settings.json (the app never edits that file for you):",
                     "Claude Code는 상태줄에 공식 한도를 알려 줘요. 아래를 ~/.claude/settings.json 맨 바깥 객체에 붙여 넣으세요(앱이 그 파일을 직접 고치지는 않아요):",
                     "Claude Code はステータスラインに公式のリミットを渡します。これを ~/.claude/settings.json の一番外側のオブジェクトに追加してください（アプリがこのファイルを書き換えることはありません）：",
                     "Claude Code 会把你的官方额度告诉它的状态栏。请把下面的内容加到 ~/.claude/settings.json 的最外层对象中（应用不会替你修改这个文件）："))
                .fixedSize(horizontal: false, vertical: true)
            Text(snippet)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
            HStack {
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
            Text(L.t("Already have a status line? Keep it, and add this as its first line instead: input=$(cat); printf '%s' \"$input\" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null; then read the JSON from $input.",
                     "이미 상태줄을 쓰고 있다면 그대로 두고, 그 스크립트 첫 줄에 input=$(cat); printf '%s' \"$input\" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null 를 넣은 뒤 JSON은 $input에서 읽으세요.",
                     "すでにステータスラインを使っている場合はそのままにして、代わりにそのスクリプトの1行目に input=$(cat); printf '%s' \"$input\" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null を入れ、JSON は $input から読んでください。",
                     "已经在用状态栏了？保留它，改为在脚本第一行加入 input=$(cat); printf '%s' \"$input\" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null，然后从 $input 读取 JSON。"))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(L.t("The numbers arrive after Claude Code's next reply. Until then Grandpa honestly says he doesn't know.",
                     "숫자는 Claude Code가 다음에 답할 때 들어와요. 그 전까지 할아버지는 솔직하게 모른다고 해요.",
                     "数値は Claude Code が次に返答したときに届きます。それまでおじいさんは正直に「わからない」と言います。",
                     "数字会在 Claude Code 下次回复后到来。在那之前，爷爷会老实地说不知道。"))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
