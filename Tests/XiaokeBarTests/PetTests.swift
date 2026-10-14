import XCTest
@testable import XiaokeBar

final class PetTests: XCTestCase {
    /// 每首歌旋律和伴奏的总拍数必须一样，否则伴奏会提前结束或拖尾
    func testSongBeatsMatch() {
        for s in Song.all {
            let melody = Song.parse(s.melody)
            let chordBeats = Song.chordList(s.chords).reduce(0) { $0 + $1.beats }
            XCTAssertEqual(melody.reduce(0) { $0 + $1.beats }, chordBeats, accuracy: 0.001, s.id)
            // 除了休止，每个音名都要能换成频率
            for (tok, n) in zip(s.melody.split(separator: " "), melody) where !tok.hasPrefix("R") && !tok.hasPrefix("@") {
                XCTAssertNotNil(n.freq, "\(s.id) 认不出 \(tok)")
            }
            for tok in s.chords.split(separator: " ") {
                let name = String(tok.split(separator: ":")[0])
                XCTAssertTrue(name == "R" || Song.voicings[name] != nil, "\(s.id) 没有和弦 \(name)")
            }
        }
    }

    /// 演奏记号和力度不影响音高和拍数
    func testScoreMarks() {
        let n = Song.parse("@pp D4:0.75~ B3:0.25 E5:2* C#5:0.5/t> R:0.5")
        XCTAssertEqual(n.count, 6)
        XCTAssertEqual(n[0].dyn, Song.dynamics["pp"]); XCTAssertEqual(n[0].beats, 0)
        XCTAssertEqual(n[1].freq!, Song.freq("D4")!, accuracy: 0.01); XCTAssertEqual(n[1].beats, 0.75); XCTAssertEqual(n[1].flags, "~")
        XCTAssertEqual(n[3].flags, "*"); XCTAssertEqual(n[4].flags, "/t>"); XCTAssertEqual(n[4].freq!, Song.freq("C#5")!, accuracy: 0.01)
        XCTAssertNil(n[5].freq); XCTAssertEqual(n[5].flags, "")
        XCTAssertEqual(ErhuFlags(Substring(n[4].flags)), [.scoop, .trill, .accent])
    }

    func testNoteFrequency() {
        XCTAssertEqual(Song.freq("A4")!, 440, accuracy: 0.01)
        XCTAssertEqual(Song.freq("C5")!, 523.25, accuracy: 0.01)
        XCTAssertEqual(Song.freq("D#5")!, 622.25, accuracy: 0.01)
        XCTAssertNil(Song.freq("R"))
    }

    /// 命令说明 → 动画：同样是跑终端，不同的事用不同的动作
    func testCommandActions() {
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "Screenshot the floating pet window"), .photo)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "Commit and push the fix"), .git)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "Build and show errors"), .building)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "部署到线上服务器"), .deploy)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "Install package dependencies"), .install)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "curl the billing API"), .network)
        XCTAssertEqual(PetAction.from(tool: "Bash", detail: "List files in directory"), .running)
        XCTAssertEqual(PetAction.from(tool: "Agent"), .delegating)
        XCTAssertEqual(PetAction.from(tool: "TodoWrite"), .planning)
        XCTAssertEqual(PetAction.from(tool: "AskUserQuestion"), .asking)
    }

    /// 每只宠物的每个动作都用 Core Graphics 后端画一遍：不能崩，而且画布上要真的有像素
    @MainActor func testEveryActionRendersWithCoreGraphics() {
        let w = 26 * 4, h = 16 * 4
        for k in Provider.allCases {
            for a in PetAction.allCases {
                guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return XCTFail() }
                var p = CGPainter(ctx: ctx)
                let pet = PetView(kind: k, action: a, pixel: 4, musicStart: Date(), bpm: 120, glasses: a == .erhu, happiness: 50, hasDog: true, hasCat: true)
                pet.render(&p, t: Date().timeIntervalSinceReferenceDate)
                let data = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
                var painted = 0
                for i in stride(from: 3, to: w * h * 4, by: 4) where data[i] > 0 { painted += 1 }
                XCTAssertGreaterThan(painted, 40, "\(k) \(a) 几乎没画出东西")
            }
        }
    }
}
