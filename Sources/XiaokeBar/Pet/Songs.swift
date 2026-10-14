import Foundation

/// 小克会弹的曲子。全部是已进入公有领域的古典曲和民谣，没有版权问题。
/// 谱子写法：旋律「音名八度:拍数」，空格分隔，R 是休止，不写拍数就是 1 拍；和弦「和弦名:拍数」，R 是这段不伴奏。
struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    let origin: String
    let region: Region
    let bpm: Double
    var meter = 4
    let style: Style
    let melody: String
    let chords: String

    enum Region: String, CaseIterable { case china, japan, west
        var label: String { switch self { case .china: L("中国"); case .japan: L("日本"); case .west: L("欧美") } }
    }

    /// 编排：谁（哪只宠物）用什么乐器、负责什么
    enum Style { case band, folk, chinese, classical, pianoSolo, erhuSolo, musicbox, guitarSolo }
    enum Role { case lead, harmony, chords, bass, drums }
    struct Part { var member: Provider; var instrument: Instrument; var role: Role }

    var parts: [Part] {
        switch style {
        case .band: [.init(member: .gemini, instrument: .flute, role: .lead), .init(member: .claude, instrument: .guitar, role: .chords),
                     .init(member: .codex, instrument: .bass, role: .bass), .init(member: .grok, instrument: .drums, role: .drums)]
        case .folk: [.init(member: .gemini, instrument: .flute, role: .lead), .init(member: .claude, instrument: .guitar, role: .chords),
                     .init(member: .codex, instrument: .bass, role: .bass)]
        case .chinese: [.init(member: .claude, instrument: .erhu, role: .lead), .init(member: .gemini, instrument: .flute, role: .harmony),
                        .init(member: .codex, instrument: .piano, role: .chords)]
        case .classical: [.init(member: .gemini, instrument: .violin, role: .lead), .init(member: .codex, instrument: .piano, role: .chords)]
        case .pianoSolo: [.init(member: .codex, instrument: .piano, role: .lead), .init(member: .codex, instrument: .piano, role: .chords)]
        case .erhuSolo: [.init(member: .claude, instrument: .erhu, role: .lead)]
        case .musicbox: [.init(member: .gemini, instrument: .musicbox, role: .lead), .init(member: .codex, instrument: .piano, role: .chords)]
        case .guitarSolo: [.init(member: .claude, instrument: .guitar, role: .lead), .init(member: .claude, instrument: .guitar, role: .chords)]
        }
    }

    /// 上台的成员和各自拿的乐器（同一只宠物只算一次，按第一次出现的乐器）
    var performers: [(member: Provider, instrument: Instrument)] {
        var seen = Set<Provider>()
        return parts.compactMap { p in seen.insert(p.member).inserted ? (p.member, p.instrument) : nil }
    }

    /// 二泉映月：演奏的宠物戴上圆墨镜，致敬阿炳
    var wearsGlasses: Bool { id == "erquan" }

    var beats: Double { Song.parse(melody).reduce(0) { $0 + $1.beats } }
    var duration: TimeInterval { beats * 60 / bpm }

    static func == (a: Song, b: Song) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [Song] = [
        // 中国
        Song(id: "jasmine", title: L("茉莉花"), origin: L("中国民歌"), region: .china, bpm: 76, style: .chinese,
             melody: "E5 E5:0.5 G5:0.5 A5:0.5 C6:0.5 C6:0.5 A5:0.5 G5 G5:0.5 A5:0.5 G5:2 E5 E5:0.5 G5:0.5 A5:0.5 C6:0.5 C6:0.5 A5:0.5 G5 G5:0.5 A5:0.5 G5:2 G5 G5 G5 E5:0.5 G5:0.5 A5 A5 G5:2 E5 D5:0.5 E5:0.5 G5 E5:0.5 D5:0.5 C5 C5:0.5 D5:0.5 C5:2",
             chords: "C:4 F:2 C:2 C:4 F:2 C:2 C:4 F:2 C:2 Am:2 G:2 C:4"),
        // 二泉映月：华彦钧（阿炳）传谱、杨荫浏记谱的通行版本（储师竹、黎松寿定弓指法）。引子 + 第 1–31 小节逐音转写，
        // 收在第 32 小节的主音上。1=G、低五度定弦（原谱注明「比一般二胡低 5 度」，和阿炳录音的音区一致）。
        // 谱上的滑音箭头、tr 颤音、倚音、颤弓、重音、力度记号都照抄了；速度按参考录音实测约 ♩=44。0.0625 拍的是倚音。
        Song(id: "erquan", title: L("二泉映月（引子与第一段）"), origin: L("华彦钧（阿炳）· 杨荫浏记谱"), region: .china, bpm: 44, style: .erhuSolo,
             melody: "@p R:0.75 E4:0.25 D4:0.25 E4:0.25 C4:0.25 B3:0.25 A3:2, @mp A3:0.75 B3:0.25 G3:0.5 G3:0.25 A3:0.25 @mf B3:1.5 D4:0.5, E4:0.5 D4:0.5 E4:0.25 D4:0.25 E4:0.25 G4:0.25 D4:0.75~ B3:0.25 D4:0.5 D4:0.25~ B3:0.25 A3:0.5 E4:0.5t D4:0.25 E4:0.25 G3:0.25 A3:0.25 B3:1.5 D4:0.5 A3:0.375> B3:0.125 D4:0.25 G4:0.25 E4:0.25 A3:0.25 B3:0.25 D4:0.25 G3:2, @f G4:0.5 E4:0.25 G4:0.25 @ff B4:0.5 B4:0.25 A4:0.25 G4:0.75~ E4:0.25 G4:0.375 A4:0.125 B4:0.25 B4:0.25 A4:0.5 G4:0.375 G4:0.125 E4:0.25 G4:0.25 A4:0.25 B4:0.25 @mp D4:2, @pp B4:0.0625~ D5:0.1875 R:0.25 @mf B4:0.25 D5:0.25 E5:0.25 D5:0.25 E5:0.25 G5:0.25 @f D5:0.75/~ B4:0.25 D5:0.25 D5:0.5> G5:0.25 E5:0.5> E5:0.5> D5:0.25 E5:0.25 D5:0.25 D5:0.25 @mp B4:0.75 D5:0.25 B4:0.375 C#5:0.125 B4:0.25 D5:0.25 A4:0.375> B4:0.125 A4:0.25 G4:0.25 E4:0.25 G4:0.25 E4:0.5> @f G4:1.75 A4:0.25 B4:0.25 D5:0.25 G4:0.5 A4:0.375 D5:0.125 B4:0.25 E5:0.25 D5:2 @pp D4:0.25 R:0.25 G3:0.25 R:0.25 @mf E4:0.25 D4:0.25 E4:0.25 G4:0.25 D4:0.75~ B3:0.25 D4:0.5 D4:0.25~ B3:0.25 A3:0.375 B3:0.125 D4:0.25 G4:0.25 E4:0.25 A3:0.25 B3:0.25 D4:0.25 G3:2, @f G4:0.5 E4:0.25~ G4:0.25 @ff B4:0.5 B4:0.25 A4:0.25 G4:0.75~ E4:0.25 G4:0.375 A4:0.125 B4:0.25 B4:0.25 A4:0.5 G4:0.375 G4:0.125 E4:0.25 G4:0.25 A4:0.25 B4:0.25 @mp D4:2, @pp D4:0.25 R:0.25 @mp B4:0.0625~ D5:0.1875 R:0.25 @mf B4:0.25 D5:0.25 B4:0.25 D5:0.25 E5:1 G5:0.5 G5:0.5 B4:0.375 D5:0.125 B4:0.25 D5:0.25 E5:0.25 D5:0.25 G5:0.25 E5:0.25 @ff D5:0.75~ B4:0.25 D5:0.25 D5:0.5> G5:0.25 E5:0.5 E5:0.5 D5:0.25 E5:0.25 D5:0.25 D5:0.25 @mp B4:0.75 D5:0.25 B4:0.375 C#5:0.125 B4:0.25 D5:0.25 A4:0.25 B4:0.25 A4:0.25 G4:0.25 E4:0.25 G4:0.25 E4:0.5 G4:0.75~ E4:0.25 G4:0.75 A4:0.25 B4:0.25 D5:0.25 G4:0.5 @f A4:0.375 D5:0.125 B4:0.125~ D5:0.125 E5:0.25 D5:1.5~ B4:0.5 @mf D5:0.5 D5:0.25 E5:0.25 D5:0.25 D5:0.25 B4:0.25 D5:0.25 @f E5:2* @mp D#5:0.0625 E5:0.9375* D5:0.0625 E5:0.9375* D#5:0.0625 E5:0.9375* D5:0.0625 E5:0.9375* @f E5:0.5 F#5:0.0625 E5:0.4375 E5:0.25 D5:0.25 E5:0.25 G5:0.25 @ff B4:0.0625~ D5:0.6875~ B4:0.25 D5:0.25 D5:0.5> G5:0.25 E5:0.5 E5:0.5 D5:0.25 E5:0.25 D5:0.25 D5:0.25 @mp B4:0.75 D5:0.25 B4:0.375 C#5:0.125 B4:0.25 D5:0.25 A4:0.25 B4:0.25 A4:0.25 G4:0.25 E4:0.25 G4:0.25 E4:0.5 G4:0.75~ E4:0.25 G4:0.75 A4:0.25 B4:0.25 D5:0.25 G4:0.5 @f A4:0.375 D5:0.125 B4:0.25 E5:0.25 D5:2 @pp D4:0.25 R:0.25 G3:0.25 R:0.25 @mf E4:0.25 D4:0.25 G4:0.25 E4:0.25 D4:0.75~ B3:0.25 D4:0.5 D4:0.25 B3:0.25 A3:0.375 B3:0.125 D4:0.25 G4:0.25 E4:0.25 A3:0.25 B3:0.25 D4:0.25 G3:2, D4:1 @f G3:0.5 G3:0.25 A3:0.25 B3:2, @mf B3:0.5 D4:0.5 E4:0.25 D4:0.25 G4:0.25 E4:0.25 D4:0.75~ B3:0.25 D4:0.5 D4:0.25 B3:0.25 A3:0.5 E4:0.5t D4:0.25 E4:0.25 G3:0.25 A3:0.25 @mp B3:0.75 A3:0.25 B3:0.75 D4:0.25 E4:0.5 A3:0.25 B3:0.25 D4:0.25 A3:0.25 B3:0.25 D4:0.25 @p G3:4",
             chords: "R:130"),
        Song(id: "songbie", title: L("送别"), origin: L("中国 · 李叔同填词"), region: .china, bpm: 76, style: .folk,
             melody: "G4 E4:0.5 G4:0.5 C5:2 A4 C5 G4:2 G4 C4:0.5 D4:0.5 E4 D4:0.5 C4:0.5 D4:4 G4 E4:0.5 G4:0.5 C5:1.5 B4:0.5 A4 C5 G4:2 G4 D4:0.5 E4:0.5 F4:1.5 B3:0.5 C4:4 A4 C5 C5:2 B4 A4:0.5 B4:0.5 C5:2 A4:0.5 B4:0.5 C5:0.5 A4:0.5 A4:0.5 G4:0.5 E4:0.5 C4:0.5 D4:4 G4 E4:0.5 G4:0.5 C5:1.5 B4:0.5 A4 C5 G4:2 G4 D4:0.5 E4:0.5 F4:1.5 B3:0.5 C4:4",
             chords: "C:4 F:2 C:2 C:4 G:4 C:4 F:2 C:2 G:4 C:4 F:4 G:2 C:2 F:2 C:2 G:4 C:4 F:2 C:2 G:4 C:4"),
        Song(id: "jacques", title: L("两只老虎"), origin: L("法国民谣"), region: .china, bpm: 120, style: .band,
             melody: "C5 D5 E5 C5 C5 D5 E5 C5 E5 F5 G5:2 E5 F5 G5:2 G5:0.5 A5:0.5 G5:0.5 F5:0.5 E5 C5 G5:0.5 A5:0.5 G5:0.5 F5:0.5 E5 C5 C5 G4 C5:2 C5 G4 C5:2",
             chords: "C:4 C:4 C:4 C:4 C:4 C:4 C:1 G:1 C:2 C:1 G:1 C:2"),
        // 日本
        Song(id: "sakura", title: L("樱花樱花"), origin: L("日本民谣"), region: .japan, bpm: 72, style: .guitarSolo,
             melody: "A4 A4 B4:2 A4 A4 B4:2 A4 B4 C5 B4 A4 B4:0.5 A4:0.5 F4:2 E4 C4 E4 F4 E4 E4:0.5 C4:0.5 B3:2 A4 B4 C5 B4 A4 B4:0.5 A4:0.5 F4:2 E4 C4 E4 F4 E4 E4:0.5 C4:0.5 B3:2 A4 A4 B4:2 A4 A4 B4:2 E4 F4 B4:0.5 A4:0.5 F4 E4:4",
             chords: "Am:4 Am:4 Am:4 Dm:4 Am:4 E:4 Am:4 Dm:4 Am:4 E:4 Am:4 Am:4 Dm:4 Am:4"),
        // 欧美
        Song(id: "jingle", title: "Jingle Bells", origin: L("美国 · 圣诞歌"), region: .west, bpm: 132, style: .band,
             melody: "E5 E5 E5:2 E5 E5 E5:2 E5 G5 C5:1.5 D5:0.5 E5:4 F5 F5 F5 F5 F5 E5 E5 E5:0.5 E5:0.5 E5 D5 D5 E5 D5:2 G5:2 E5 E5 E5:2 E5 E5 E5:2 E5 G5 C5:1.5 D5:0.5 E5:4 F5 F5 F5 F5 F5 E5 E5 E5:0.5 E5:0.5 G5 G5 F5 D5 C5:4",
             chords: "C:4 C:4 C:4 C:4 F:4 C:4 G:4 G:4 C:4 C:4 C:4 C:4 F:4 C:4 G:4 C:4"),
        Song(id: "saints", title: "When the Saints", origin: L("美国 · 爵士名曲"), region: .west, bpm: 132, style: .band,
             melody: "C5 E5 F5 G5:5 C5 E5 F5 G5:5 C5 E5 F5 G5:2 E5:2 C5:2 E5:2 D5:5 E5 E5 D5 C5:3 C5 E5:2 G5:2 G5 F5:4 E5 F5 G5:2 E5:2 C5:2 D5:2 C5:4",
             chords: "R:3 C:24 G:8 C:8 F:5 C:8 G:2 C:4"),
        Song(id: "cancan", title: L("康康舞"), origin: L("法国 · 奥芬巴赫"), region: .west, bpm: 152, style: .band,
             melody: "C5 D5:0.5 F5:0.5 E5:0.5 D5:0.5 G5:0.5 G5:0.5 G5:0.5 A5:0.5 E5:0.5 F5:0.5 D5 D5:0.5 F5:0.5 E5:0.5 D5:0.5 C5:0.5 C6:0.5 B5:0.5 A5:0.5 G5:0.5 F5:0.5 E5:0.5 D5:0.5 C5:0.5 D5:0.5 E5:0.5 C5:0.5 D5 C5 D5:0.5 F5:0.5 E5:0.5 D5:0.5 G5:0.5 G5:0.5 G5:0.5 A5:0.5 E5:0.5 F5:0.5 D5 D5:0.5 F5:0.5 E5:0.5 D5:0.5 C5:0.5 C6:0.5 B5:0.5 A5:0.5 G5:0.5 F5:0.5 E5:0.5 D5:0.5 C5:0.5 G4:0.5 C5:2",
             chords: "C:2 G:2 C:2 G:2 C:2 F:2 G:4 C:2 G:2 C:2 G:2 C:2 F:2 G:2 C:2"),
        Song(id: "birthday", title: L("生日快乐"), origin: L("美国"), region: .west, bpm: 96, meter: 3, style: .band,
             melody: "G4:0.75 G4:0.25 A4 G4 C5 B4:2 G4:0.75 G4:0.25 A4 G4 D5 C5:2 G4:0.75 G4:0.25 G5 E5 C5 B4 A4:2 F5:0.75 F5:0.25 E5 C5 D5 C5:3",
             chords: "C:3 G:3 G:3 C:3 C:3 F:4 C:2 G:2 C:3"),
        Song(id: "auld", title: L("友谊地久天长"), origin: L("苏格兰民谣"), region: .west, bpm: 88, style: .folk,
             melody: "G4 C5:1.5 C5:0.5 C5 E5 D5:1.5 C5:0.5 D5 E5 C5:1.5 C5:0.5 E5 G5 A5:3 A5 G5:1.5 E5:0.5 E5 C5 D5:1.5 C5:0.5 D5 E5 C5:1.5 A4:0.5 A4 G4 C5:3",
             chords: "R:1 C:4 G:4 C:4 F:4 C:4 G:4 F:2 G:2 C:3"),
        Song(id: "greensleeves", title: "Greensleeves", origin: L("英格兰民谣"), region: .west, bpm: 96, meter: 3, style: .folk,
             melody: "A4 C5:2 D5 E5:1.5 F5:0.5 E5 D5:2 B4 G4:1.5 A4:0.5 B4 C5:2 A4 A4:1.5 G#4:0.5 A4 B4:2 G#4 E4:2 A4 C5:2 D5 E5:1.5 F5:0.5 E5 D5:2 B4 G4:1.5 A4:0.5 B4 C5:1.5 B4:0.5 A4 G#4:1.5 F#4:0.5 G#4 A4:3",
             chords: "R:1 Am:3 C:3 G:3 Em:3 Am:3 E:3 E:3 Am:3 Am:3 C:3 G:3 Em:3 Am:3 E:3 Am:3"),
        Song(id: "grace", title: "Amazing Grace", origin: L("美国 · 赞美诗"), region: .west, bpm: 80, meter: 3, style: .classical,
             melody: "G4 C5:2 E5:0.5 C5:0.5 E5:2 D5 C5:2 A4 G4:2 G4 C5:2 E5:0.5 C5:0.5 E5:2 D5 G5:3 G5:2 E5 G5:2 E5:0.5 C5:0.5 E5:2 D5 C5:2 A4 G4:2 G4 C5:2 E5:0.5 C5:0.5 E5:2 D5 C5:3",
             chords: "R:1 C:3 C:3 F:3 C:3 C:3 C:3 G:3 G:3 C:3 C:3 F:3 C:3 C:3 G:3 C:3"),
        Song(id: "ode", title: L("欢乐颂"), origin: L("德国 · 贝多芬"), region: .west, bpm: 112, style: .classical,
             melody: "E5 E5 F5 G5 G5 F5 E5 D5 C5 C5 D5 E5 E5:1.5 D5:0.5 D5:2 E5 E5 F5 G5 G5 F5 E5 D5 C5 C5 D5 E5 D5:1.5 C5:0.5 C5:2",
             chords: "C:4 G:4 C:4 G:4 C:4 G:4 C:4 G:2 C:2"),
        Song(id: "canon", title: L("卡农"), origin: L("德国 · 帕赫贝尔"), region: .west, bpm: 72, style: .classical,
             melody: "E5:2 D5:2 C5:2 B4:2 A4:2 G4:2 A4:2 B4:2 C5:0.5 E5:0.5 G5:0.5 E5:0.5 B4:0.5 D5:0.5 G5:0.5 D5:0.5 C5:0.5 E5:0.5 A5:0.5 E5:0.5 B4:0.5 E5:0.5 G5:0.5 E5:0.5 A4:0.5 C5:0.5 F5:0.5 C5:0.5 G4:0.5 C5:0.5 E5:0.5 C5:0.5 A4:0.5 C5:0.5 F5:0.5 C5:0.5 B4:0.5 D5:0.5 G5:0.5 D5:0.5 C5:4",
             chords: "C:2 G:2 Am:2 Em:2 F:2 C:2 F:2 G:2 C:2 G:2 Am:2 Em:2 F:2 C:2 F:2 G:2 C:4"),
        Song(id: "minuet", title: L("G 大调小步舞曲"), origin: L("德国 · 佩措尔德"), region: .west, bpm: 116, meter: 3, style: .classical,
             melody: "D5 G4:0.5 A4:0.5 B4:0.5 C5:0.5 D5 G4 G4 E5 C5:0.5 D5:0.5 E5:0.5 F#5:0.5 G5 G4 G4 C5 D5:0.5 C5:0.5 B4:0.5 A4:0.5 B4 C5:0.5 B4:0.5 A4:0.5 G4:0.5 F#4 G4:0.5 A4:0.5 B4:0.5 G4:0.5 A4:3 D5 G4:0.5 A4:0.5 B4:0.5 C5:0.5 D5 G4 G4 E5 C5:0.5 D5:0.5 E5:0.5 F#5:0.5 G5 G4 G4 C5 D5:0.5 C5:0.5 B4:0.5 A4:0.5 B4 C5:0.5 B4:0.5 A4:0.5 G4:0.5 A4 B4:0.5 A4:0.5 G4:0.5 F#4:0.5 G4:3",
             chords: "G:3 G:3 C:3 G:3 C:3 G:3 D:3 D:3 G:3 G:3 C:3 G:3 C:3 G:3 D:3 G:3"),
        Song(id: "elise", title: L("致爱丽丝"), origin: L("德国 · 贝多芬"), region: .west, bpm: 84, meter: 3, style: .pianoSolo,
             melody: "E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1.5 C4:0.5 E4:0.5 A4:0.5 B4:1.5 E4:0.5 G#4:0.5 B4:0.5 C5:1.5 E4:0.5 E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1.5 C4:0.5 E4:0.5 A4:0.5 B4:1.5 E4:0.5 C5:0.5 B4:0.5 A4:3",
             chords: "R:4 Am:3 E:3 Am:2 R:4 Am:3 E:3 Am:3"),
        Song(id: "twinkle", title: L("小星星"), origin: L("法国民谣 · 莫扎特变奏"), region: .west, bpm: 104, style: .musicbox,
             melody: "C5 C5 G5 G5 A5 A5 G5:2 F5 F5 E5 E5 D5 D5 C5:2 G5 G5 F5 F5 E5 E5 D5:2 G5 G5 F5 F5 E5 E5 D5:2 C5 C5 G5 G5 A5 A5 G5:2 F5 F5 E5 E5 D5 D5 C5:2",
             chords: "C:2 C:2 F:2 C:2 F:2 C:2 G:2 C:2 C:2 F:2 C:2 G:2 C:2 F:2 C:2 G:2 C:2 C:2 F:2 C:2 F:2 C:2 G:2 C:2"),
        Song(id: "london", title: L("伦敦桥"), origin: L("英国童谣"), region: .west, bpm: 112, style: .musicbox,
             melody: "G5:1.5 A5:0.5 G5 F5 E5 F5 G5:2 D5 E5 F5:2 E5 F5 G5:2 G5:1.5 A5:0.5 G5 F5 E5 F5 G5:2 D5:2 G5:2 E5 C5:3",
             chords: "C:4 C:4 G:4 C:4 C:4 C:4 G:4 C:4"),
    ]

    /// flags：演奏记号（~ 滑到下一个音、/ 从下滑入、t 颤音、* 颤弓、> 重音、, 断一下）；dyn：力度记号 @pp…@ff，自己不占拍子
    struct Note { var freq: Double?; var beats: Double; var flags = ""; var dyn: Double? }

    static let dynamics: [String: Double] = ["pp": 0.28, "p": 0.38, "mp": 0.5, "mf": 0.64, "f": 0.8, "ff": 1.0]
    private static let flagChars = Set("~/t*>,")

    /// 「C#5:1.5~」→ 频率 + 拍数 + 记号；「@mf」→ 力度
    static func parse(_ s: String) -> [Note] {
        s.split(separator: " ").map { tok in
            if tok.hasPrefix("@") { return Note(freq: nil, beats: 0, dyn: dynamics[String(tok.dropFirst())] ?? 0.64) }
            let flags = String(tok.reversed().prefix { flagChars.contains($0) }.reversed())
            let body = tok.dropLast(flags.count)
            let parts = body.split(separator: ":")
            let beats = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
            return Note(freq: freq(String(parts[0])), beats: beats, flags: flags)
        }
    }

    static func freq(_ name: String) -> Double? {
        guard name != "R", let letter = name.first, let octave = Int(name.filter(\.isNumber)) else { return nil }
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var semi = base[letter] else { return nil }
        if name.contains("#") { semi += 1 }
        if name.dropFirst().contains("b") { semi -= 1 }
        let midi = (octave + 1) * 12 + semi
        return 440 * pow(2, Double(midi - 69) / 12)
    }

    /// 和弦按弦的频率（低音到高音，标准调弦的开放和弦）
    static let voicings: [String: [Double]] = [
        "C": [130.81, 164.81, 196.00, 261.63, 329.63],
        "G": [98.00, 123.47, 146.83, 196.00, 246.94, 392.00],
        "Am": [110.00, 164.81, 220.00, 261.63, 329.63],
        "F": [87.31, 130.81, 174.61, 220.00, 261.63, 349.23],
        "Dm": [146.83, 220.00, 293.66, 349.23],
        "Em": [82.41, 123.47, 164.81, 196.00, 246.94, 329.63],
        "E": [82.41, 123.47, 164.81, 207.65, 246.94, 329.63],
        "D": [146.83, 220.00, 293.66, 369.99],
    ]

    static func chordList(_ s: String) -> [(notes: [Double], beats: Double)] {
        s.split(separator: " ").map { tok in
            let parts = tok.split(separator: ":")
            return (voicings[String(parts[0])] ?? [], parts.count > 1 ? Double(parts[1]) ?? 4 : 4)
        }
    }
}

import SwiftUI

/// 「弹一首歌」菜单：顶栏吉他按钮、宠物右键菜单共用
struct SongMenuItems: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(L("随手扫一段 🎸")) { model.perform(.guitar, seconds: 9) }
        ForEach(Song.Region.allCases, id: \.self) { r in
            Section(r.label) {
                ForEach(Song.all.filter { $0.region == r }) { s in
                    Button((model.nowPlaying?.song == s ? "♪ " : "") + s.title + "  · " + s.performers.map(\.instrument.label).joined(separator: "+")) { model.play(s) }
                }
            }
        }
        if model.nowPlaying != nil {
            Divider()
            Button(L("停止演奏")) { model.stopSong() }
        }
    }
}

/// 主奏宠物看的「旋律轨」：某一拍正在拉哪个音、弓拉到哪了。按手指位置、弓的来回画动画用。
/// 换弓规则和二胡发声器一样（Arranger.erhuLine），画面上的换弓和听到的换弓对得上
final class MelodyTrack: @unchecked Sendable {
    private var starts: [Double] = [], lengths: [Double] = [], midis: [Double?] = []
    private var strokeStart: [Double] = [], strokeLen: [Double] = [], strokeDown: [Bool] = []
    private var strokeOf: [Int] = []

    private static let lock = NSLock()
    private static var cache: [String: MelodyTrack] = [:]

    static func of(_ songID: String) -> MelodyTrack? {
        lock.lock(); defer { lock.unlock() }
        if let t = cache[songID] { return t }
        guard let song = Song.all.first(where: { $0.id == songID }) else { return nil }
        let t = MelodyTrack(song)
        cache[songID] = t
        return t
    }

    private init(_ song: Song) {
        var t = 0.0
        for n in Song.parse(song.melody) where n.dyn == nil {
            starts.append(t); lengths.append(n.beats)
            midis.append(n.freq.map { 69 + 12 * log2($0 / 440) })
            t += n.beats
        }
        var down = false
        for i in starts.indices {
            let prevRest = i == 0 || midis[i - 1] == nil
            let grace = lengths[i] < 0.1 || (i > 0 && lengths[i - 1] < 0.1)
            let onBeat = abs(starts[i] - starts[i].rounded()) < 0.001
            let prevLong = i > 0 && lengths[i - 1] >= 1
            let bow = midis[i] != nil && (prevRest || (!grace && (onBeat || lengths[i] >= 1 || prevLong)))
            if bow || strokeStart.isEmpty {
                down.toggle()
                strokeStart.append(starts[i]); strokeLen.append(0); strokeDown.append(down)
            }
            strokeLen[strokeLen.count - 1] = starts[i] + lengths[i] - strokeStart[strokeStart.count - 1]
            strokeOf.append(strokeStart.count - 1)
        }
    }

    /// midi：正在响的音（休止时 nil）；bow：0…1 弓的位置（推弓从 0 到 1，拉弓从 1 到 0）
    func at(_ beat: Double) -> (midi: Double?, bow: Double)? {
        guard !starts.isEmpty, beat >= 0, beat < starts[starts.count - 1] + lengths[lengths.count - 1] else { return nil }
        // 二分找当前音
        var lo = 0, hi = starts.count - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if starts[m] <= beat { lo = m } else { hi = m - 1 } }
        let s = strokeOf[lo]
        let p = min(1, max(0, (beat - strokeStart[s]) / max(0.05, strokeLen[s])))
        return (midis[lo], strokeDown[s] ? p : 1 - p)
    }
}
