import AppKit
import SwiftUI
import TokenPetAssets

extension Award {
    /// What the magpie says.
    var announcement: String {
        switch self {
        case .rank(let r): return L.t("Caw caw! A new title:\n\(Titles.ladder[r].name())", "깍깍! 새 칭호예요\n\(Titles.ladder[r].name())",
                                           "カチカチ! 新しい称号です\n\(Titles.ladder[r].name())", "喳喳! 新称号\n\(Titles.ladder[r].name())")
        case .feat(let f): return L.t("Caw caw! An achievement:\n\(Titles.name(f))", "깍깍! 업적이에요\n\(Titles.name(f))",
                                           "カチカチ! 実績です\n\(Titles.name(f))", "喳喳! 新成就\n\(Titles.name(f))")
        }
    }
}

/// The current title and how far it is to the next. Shared by the popover and the titles window.
struct TitleProgress: View {
    let lifetime: Double
    var body: some View {
        let r = Titles.rank(lifetime), p = Titles.progress(lifetime)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "rosette").foregroundColor(TitleCard.gold)
                Text(r >= 0 ? Titles.ladder[r].name() : L.t("No title yet", "아직 칭호 없음", "まだ称号なし", "还没有称号")).font(.subheadline.weight(.semibold))
                Spacer()
                if let p {
                    let next = Titles.ladder[p.next].name()
                    Text(L.t("\(Fmt.tokens(Int(p.left))) to “\(next)”", "‘\(next)’까지 \(Fmt.tokens(Int(p.left)))",
                             "「\(next)」まであと\(Fmt.tokens(Int(p.left)))", "距“\(next)”还差\(Fmt.tokens(Int(p.left)))"))
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                } else {
                    Text(L.t("The top title", "가장 높은 칭호", "最高の称号", "最高称号")).font(.caption).foregroundColor(.secondary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(TitleCard.gold).frame(width: max(4, g.size.width * CGFloat(p?.fraction ?? 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

/// The shareable card: the pixel scene, the title, and totals. Nothing personal (no name, no account, no dates).
struct TitleCard: View {
    static let gold = Color(red: 0.86, green: 0.65, blue: 0.2)
    static let size = CGSize(width: 560, height: 236)
    let lifetime: Double
    let mountainLeft: Double
    let mountainsMoved: Int
    let feats: Int

    var body: some View {
        let r = Titles.rank(lifetime)
        HStack(spacing: 18) {
            Image(nsImage: Yugong.scene(SceneInfo(state: .lively, carrier: 0.5, mountainLeft: mountainLeft, grandson: nil, night: false),
                                        t: 0.9, size: PopoverView.sceneSize))
                .interpolation(.none)
                .frame(width: PopoverView.sceneSize.width, height: PopoverView.sceneSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("Token Yugong", "토큰 우공", "トークン愚公", "令牌愚公")).font(.caption.weight(.bold)).foregroundColor(.white.opacity(0.6))
                Text(r >= 0 ? Titles.ladder[r].name() : L.t("No title yet", "아직 칭호 없음", "まだ称号なし", "还没有称号"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(Self.gold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.t("Title \(r + 1) of \(Titles.ladder.count)", "칭호 \(Titles.ladder.count)단계 중 \(r + 1)단계",
                         "称号 \(Titles.ladder.count)段階中 \(r + 1)段階", "称号 第\(r + 1)级 / 共\(Titles.ladder.count)级"))
                    .font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.8))
                Spacer(minLength: 4)
                stat(L.t("Tokens carried", "옮긴 토큰", "運んだトークン", "搬运的令牌"), Fmt.tokens(Int(lifetime)))
                stat(L.t("Mountains moved", "옮긴 산", "移した山", "移走的山"), "\(mountainsMoved)")
                stat(L.t("Achievements", "업적", "実績", "成就"), "\(feats) / \(Feat.allCases.count)")
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.14, blue: 0.24), Color(red: 0.27, green: 0.2, blue: 0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.65))
            Spacer()
            Text(value).font(.callout.monospacedDigit().weight(.bold)).foregroundColor(.white)
        }
    }

    init(model: UsageModel) {
        lifetime = model.lifetime
        mountainLeft = model.mountainLeft
        mountainsMoved = model.demoLifetime.map { Int($0 / model.mountain.size) } ?? model.mountain.index
        feats = model.titles.feats.count
    }

    /// The card as PNG data, at 2x.
    @MainActor static func png(_ model: UsageModel) -> Data? {
        let r = ImageRenderer(content: TitleCard(model: model))
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

/// Every title and achievement, earned or still locked, and the card to save.
struct TitlesView: View {
    @ObservedObject var model: UsageModel
    var scrolls = true   // stills: ImageRenderer draws no scroll view
    @State private var saved: String?

    var body: some View {
        if scrolls { ScrollView { content }.frame(width: 452, height: 560) } else { content.frame(width: 452) }
    }

    private var content: some View {
        let r = Titles.rank(model.lifetime)
        return VStack(alignment: .leading, spacing: 12) {
            TitleProgress(lifetime: model.lifetime)
            TitleCard(model: model)
                .scaleEffect(0.75, anchor: .topLeading)
                .frame(width: TitleCard.size.width * 0.75, height: TitleCard.size.height * 0.75, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Button(L.t("Save the title card as PNG…", "칭호 카드를 PNG로 저장…", "称号カードをPNGで保存…", "将称号卡存为PNG…")) { saveCard() }
                if let saved { Text(saved).font(.caption).foregroundColor(.secondary) }
        }
            Divider()
            Text(L.t("Titles: every token carried, all mountains together", "칭호: 옮긴 토큰 모두 (산 전부 합쳐서)",
                     "称号: 運んだトークンの合計(すべての山)", "称号: 搬运的令牌总数(所有山合计)"))
                .font(.caption.weight(.bold)).foregroundColor(.secondary)
            ForEach(Titles.ladder.indices, id: \.self) { i in
                row(earned: i <= r, name: Titles.ladder[i].name(), note: Fmt.tokens(Int(Titles.ladder[i].tokens)))
            }
            Divider()
            Text(L.t("Achievements", "업적", "実績", "成就")).font(.caption.weight(.bold)).foregroundColor(.secondary)
            ForEach(Feat.allCases, id: \.self) { f in
                row(earned: model.titles.feats[f] != nil, name: Titles.name(f), note: Titles.detail(f))
            }
        }
        .padding(16)
    }

    private func row(earned: Bool, name: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: earned ? "checkmark.seal.fill" : "lock.fill")
                .foregroundColor(earned ? TitleCard.gold : .secondary)
                .accessibilityLabel(earned ? L.t("Earned", "받음", "獲得", "已获得") : L.t("Locked", "아직", "未獲得", "未解锁"))
            Text(name).font(.callout.weight(earned ? .semibold : .regular)).foregroundColor(earned ? .primary : .secondary)
            Spacer()
            Text(note).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 220, alignment: .trailing)
        }
    }

    @MainActor private func saveCard() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = "token-yugong-title.png"
        guard p.runModal() == .OK, let url = p.url, let data = TitleCard.png(model) else { return }
        do { try data.write(to: url); saved = L.t("Saved.", "저장했어요.", "保存しました。", "已保存。") }
        catch { saved = L.t("Could not save: \(error.localizedDescription)", "저장하지 못했어요: \(error.localizedDescription)",
                                 "保存できませんでした: \(error.localizedDescription)", "无法保存: \(error.localizedDescription)") }
    }
}
