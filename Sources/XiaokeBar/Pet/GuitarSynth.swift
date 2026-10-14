import AVFoundation

/// 宠物乐队会用的乐器
enum Instrument: String, CaseIterable, Sendable {
    case guitar, piano, bass, drums, flute, violin, erhu, musicbox

    var label: String {
        switch self {
        case .guitar: L("吉他"); case .piano: L("钢琴"); case .bass: L("贝斯"); case .drums: L("鼓")
        case .flute: L("长笛"); case .violin: L("小提琴"); case .erhu: L("二胡"); case .musicbox: L("八音盒")
        }
    }

    var action: PetAction {
        switch self {
        case .guitar: .guitar; case .piano: .piano; case .bass: .bass; case .drums: .drums
        case .flute: .flute; case .violin: .violin; case .erhu: .erhu; case .musicbox: .musicbox
        }
    }
}

/// 宠物乐队的声音：全部实时合成，不带任何音频文件。
/// - 吉他、贝斯：Karplus-Strong 拨弦（一段噪声在延迟线里反复低通，听起来就是真的拨弦）
/// - 钢琴、八音盒、长笛、小提琴、二胡：几个泛音叠加 + 各自的包络；弦乐带揉弦，二胡还有换音时的滑音
/// - 鼓：底鼓是往下滑的正弦，军鼓是噪声 + 低音，踩镲是高频噪声
final class GuitarSynth: @unchecked Sendable {
    static let shared = GuitarSynth()

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode!
    private let lock = NSLock()
    private var strings: [PluckedString] = []
    private var tones: [Tone] = []
    private var drums: [Drum] = []
    private var erhu: ErhuVoice
    private var events: [Event] = []      // 按采样点排好
    private var next = 0
    private var clock = 0
    private var volume: Float = 0.6
    let rate: Double = 44_100
    private var started = false
    private var stopWork: DispatchWorkItem?

    enum DrumKind: Sendable { case kick, snare, hat }

    struct Event {
        var at: Int
        var kind: Kind
        enum Kind {
            case pluck(freq: Double, amp: Double, decay: Float)
            case tone(Instrument, freq: Double, amp: Double, dur: Double, slideFrom: Double?)
            case drum(DrumKind, amp: Double)
            case erhu(ErhuNote)
        }
    }

    struct PluckedString {
        var buf: [Float]
        var idx = 0
        var decay: Float
        var life: Int
        mutating func next() -> Float {
            let n = buf.count
            let cur = buf[idx]
            let nxt = buf[(idx + 1) % n]
            // 两点平均 = 低通，乘衰减系数 = 能量慢慢散掉
            buf[idx] = (cur + nxt) * 0.5 * decay
            idx = (idx + 1) % n
            life -= 1
            return cur
        }
    }

    /// 加法合成的一个音
    struct Tone {
        var inst: Instrument
        var freq: Double
        var from: Double
        var amp: Double
        var dur: Double          // 按住多久（秒）
        var t: Double = 0
        var phase: Double = 0
        var lp: Double = 0
        var done = false

        static let weights: [Instrument: [Double]] = [
            .piano: [1, 0.5, 0.28, 0.14, 0.07],
            .flute: [1, 0.12, 0.05],
            .violin: [1, 0.55, 0.38, 0.28, 0.2, 0.15, 0.1, 0.07],
            .erhu: [1, 0.85, 0.75, 0.42, 0.3, 0.16, 0.08],
            .musicbox: [1],
        ]

        mutating func next(_ dt: Double) -> Float {
            t += dt
            // 滑音：二胡换音时从上一个音滑过来
            var f = freq
            if from != freq, t < 0.08 { f = from * pow(freq / from, t / 0.08) }
            // 揉弦 / 气息颤音：音出来一会儿以后才开始
            switch inst {
            case .violin where t > 0.18: f *= 1 + 0.005 * sin(t * 2 * .pi * 5.5)
            case .erhu where t > 0.1: f *= 1 + 0.011 * sin(t * 2 * .pi * 6)
            case .flute where t > 0.2: f *= 1 + 0.003 * sin(t * 2 * .pi * 5)
            default: break
            }
            phase += 2 * .pi * f * dt
            if phase > 2 * .pi * 1000 { phase -= 2 * .pi * 1000 }
            var s = 0.0
            let env: Double
            switch inst {
            case .piano:
                // 每个泛音衰减速度不同，高音衰减得快
                for (k, a) in Tone.weights[.piano]!.enumerated() {
                    s += a * exp(-t * (1.1 + Double(k) * 0.9 + freq / 700)) * sin(Double(k + 1) * phase)
                }
                env = min(1, t / 0.004) * (t > dur + 0.25 ? max(0, 1 - (t - dur - 0.25) / 0.12) : 1)
                if t > dur + 0.4 { done = true }
            case .musicbox:
                // 正弦 + 一个不成整数倍的泛音，听起来像金属簧片
                s = sin(phase) * exp(-t * 2.6) + 0.32 * sin(phase * 2.76) * exp(-t * 6) + 0.12 * sin(phase * 5.4) * exp(-t * 10)
                env = min(1, t / 0.002)
                if t > 1.6 { done = true }
            default:
                for (k, a) in (Tone.weights[inst] ?? [1]).enumerated() { s += a * sin(Double(k + 1) * phase) }
                let attack = inst == .flute ? 0.07 : (inst == .erhu ? 0.06 : 0.09)
                let release = 0.14
                env = min(1, t / attack) * (t > dur ? max(0, 1 - (t - dur) / release) : 1)
                if t > dur + release { done = true }
                if inst == .flute { s += Double.random(in: -1...1) * 0.012 }           // 气声
                if inst == .erhu || inst == .violin { s += Double.random(in: -1...1) * 0.012 } // 弓噪
                // 一点低通，去掉合成的刺耳感
                lp += (s - lp) * (inst == .erhu ? 0.45 : 0.35)
                s = lp
            }
            return Float(s * env * amp)
        }
    }

    struct Drum {
        var kind: DrumKind
        var amp: Double
        var t: Double = 0
        var phase: Double = 0
        var prev: Double = 0
        var done = false

        mutating func next(_ dt: Double) -> Float {
            t += dt
            var s = 0.0
            switch kind {
            case .kick:
                let f = 45 + 75 * exp(-t * 30)
                phase += 2 * .pi * f * dt
                s = sin(phase) * exp(-t * 16)
                if t > 0.4 { done = true }
            case .snare:
                phase += 2 * .pi * 190 * dt
                s = Double.random(in: -1...1) * exp(-t * 22) * 0.7 + sin(phase) * exp(-t * 30) * 0.4
                if t > 0.25 { done = true }
            case .hat:
                let n = Double.random(in: -1...1)
                s = (n - prev) * 0.5 * exp(-t * 70)     // 一阶高通：只留高频的「嚓」
                prev = n
                if t > 0.08 { done = true }
            }
            return Float(s * amp)
        }
    }

    private init() {
        erhu = ErhuVoice(rate: rate)
        node = AVAudioSourceNode { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            let list = UnsafeMutableAudioBufferListPointer(abl)
            self.lock.lock()
            for f in 0..<Int(frameCount) {
                let s = self.renderSample()
                for b in list { b.mData?.assumingMemoryBound(to: Float.self)[f] = s }
            }
            self.lock.unlock()
            return noErr
        }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
    }

    /// 算一个采样点（调用方持锁）
    private func renderSample() -> Float {
        while next < events.count, events[next].at <= clock {
            switch events[next].kind {
            case .pluck(let f, let a, let d): strings.append(Self.pluck(freq: f, amp: a, rate: rate, decay: d))
            case .tone(let inst, let f, let a, let dur, let from): tones.append(Tone(inst: inst, freq: f, from: from ?? f, amp: a, dur: dur))
            case .drum(let k, let a): drums.append(Drum(kind: k, amp: a))
            case .erhu(let n): erhu.start(n)
            }
            next += 1
        }
        let dt = 1 / rate
        var s: Float = 0
        for i in strings.indices { s += strings[i].next() }
        for i in tones.indices { s += tones[i].next(dt) }
        for i in drums.indices { s += drums[i].next(dt) }
        if !erhu.silent { s += erhu.next() }
        if !strings.isEmpty { strings.removeAll { $0.life <= 0 } }
        if !tones.isEmpty { tones.removeAll(where: \.done) }
        if !drums.isEmpty { drums.removeAll(where: \.done) }
        clock += 1
        return tanhf(s * 0.9) * volume * 0.85      // 软限幅，叠加再多也不会爆音
    }

    private static func pluck(freq: Double, amp: Double, rate: Double, decay: Float = 0.996) -> PluckedString {
        let n = max(2, Int(rate / freq))
        var buf = [Float](repeating: 0, count: n)
        // 白噪声 + 轻微平滑，模拟拨片的「沙」声
        var prev: Float = 0
        for i in 0..<n {
            let w = Float.random(in: -1...1)
            prev = prev * 0.3 + w * 0.7
            buf[i] = prev * Float(amp)
        }
        return PluckedString(buf: buf, decay: decay, life: Int(rate * 2.6))
    }

    // MARK: 演奏

    /// 随手扫一段 C - G - Am - F（约 4 秒）
    func strum(volume: Double) {
        let chords = ["C", "G", "Am", "F"].map { Song.voicings[$0]! }
        let beat = Int(rate * 0.5)
        let pattern: [(Double, Bool, Double)] = [(0, true, 1.0), (0.5, false, 0.55), (1.0, true, 0.8), (1.5, false, 0.6)]  // 下-上-下-上
        var list: [Event] = []
        var t = Int(rate * 0.05)
        for chord in chords {
            for (offset, down, amp) in pattern {
                let notes = down ? chord : Array(chord.reversed().prefix(4))
                for (k, f) in notes.enumerated() {
                    list.append(Event(at: t + Int(offset * Double(beat)) + k * Int(rate * 0.012), kind: .pluck(freq: f, amp: amp * 0.55, decay: 0.996)))
                }
            }
            t += beat * 2
        }
        schedule(list, volume: volume, start: true)
    }

    /// 按编排弹一首（换歌时上一首立刻停）。返回要弹多久。
    @discardableResult
    func play(_ song: Song, volume: Double, startEngine: Bool = true) -> TimeInterval {
        schedule(Arranger.events(for: song, rate: rate), volume: volume, start: startEngine)
        return song.duration + 0.1
    }

    /// 停下：还没弹的音不弹了，已经在响的自然消失
    func stop() {
        lock.lock(); events = []; next = 0; erhu.release(); lock.unlock()
    }

    /// 离线渲染（自检用：检查音量和长度，不出声）
    func renderOffline(_ song: Song, volume: Double, onlyPart: Int? = nil) -> [Float] {
        let d: TimeInterval
        if let p = onlyPart {
            schedule(Arranger.events(for: song, rate: rate, only: p), volume: volume, start: false)
            d = song.duration + 0.1
        } else {
            d = play(song, volume: volume, startEngine: false)
        }
        lock.lock(); defer { lock.unlock() }
        let n = Int((d + 2.6) * rate)
        var out: [Float] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(renderSample()) }
        return out
    }

    private func schedule(_ list: [Event], volume: Double, start: Bool) {
        lock.lock()
        self.volume = Float(max(0, min(1, volume)))
        let base = clock + Int(rate * 0.08)
        events = list.map { var e = $0; e.at += base; return e }.sorted { $0.at < $1.at }
        next = 0
        erhu.release()
        lock.unlock()
        if start { startEngine() }
    }

    private func startEngine() {
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        scheduleIdleCheck()
    }

    /// 弹完、声音也停了，就关掉音频引擎，不常驻占用
    private func scheduleIdleCheck() {
        stopWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let idle = self.next >= self.events.count && self.strings.isEmpty && self.tones.isEmpty && self.drums.isEmpty && self.erhu.silent
            self.lock.unlock()
            if idle { self.engine.stop(); self.started = false } else { self.scheduleIdleCheck() }
        }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }
}

/// 把一首曲子按它的编排拆成每件乐器的音符事件
enum Arranger {
    /// only：只要第几个声部（自检时单独量每件乐器的响度用）
    static func events(for song: Song, rate: Double, only: Int? = nil) -> [GuitarSynth.Event] {
        let beat = rate * 60 / song.bpm
        var out: [GuitarSynth.Event] = []
        func at(_ b: Double) -> Int { Int(b * beat) }
        let melody = Song.parse(song.melody)
        let chords = Song.chordList(song.chords)
        let secPerBeat = 60 / song.bpm

        for (pi, part) in song.parts.enumerated() where only == nil || only == pi {
            switch part.role {
            case .lead where part.instrument == .erhu, .harmony where part.instrument == .erhu:
                out += erhuLine(melody, beat: beat, octave: part.role == .harmony ? 2 : 1, levelScale: part.role == .harmony ? 0.5 : 1)
            case .lead, .harmony:
                // 和声声部原来高八度，长笛吹到 2 kHz 很刺耳：改成和主旋律同音齐奏（民乐里笛子和二胡常这样）
                let octave = part.role == .harmony && part.instrument != .flute ? 2.0 : 1.0
                // 八音盒衰减快要给大一点；小提琴泛音多、听着偏响，收一点（按 A 加权响度对齐各件乐器）
                let amp = part.role == .harmony ? 0.2 : (part.instrument == .guitar ? 0.8 : (part.instrument == .musicbox ? 0.75 : (part.instrument == .violin ? 0.34 : 0.42)))
                var t = 0.0
                for n in melody where n.dyn == nil {
                    if let f0 = n.freq {
                        let f = f0 * octave
                        switch part.instrument {
                        case .guitar, .bass:
                            // 吉他独奏的旋律常在低音区、拨完就衰减，音量和延音都给足一点
                            let solo = song.style == .guitarSolo
                            out.append(.init(at: at(t), kind: .pluck(freq: f, amp: solo ? 1.25 : amp, decay: n.beats >= 2 || solo ? 0.998 : 0.9965)))
                        default:
                            out.append(.init(at: at(t), kind: .tone(part.instrument, freq: f, amp: amp, dur: max(0.08, n.beats * secPerBeat * 0.92), slideFrom: nil)))
                        }
                    }
                    t += n.beats
                }
            case .chords:
                var t = 0.0
                for c in chords {
                    if !c.notes.isEmpty {
                        for b in 0..<Int(c.beats.rounded(.up)) {
                            let x = at(t + Double(b))
                            switch part.instrument {
                            case .piano:
                                // 左手低音 + 右手分解和弦
                                if b == 0 {
                                    out.append(.init(at: x, kind: .tone(.piano, freq: c.notes[0] / 2, amp: 0.4, dur: secPerBeat * 1.5, slideFrom: nil)))
                                    for f in c.notes.suffix(3) { out.append(.init(at: x, kind: .tone(.piano, freq: f, amp: 0.14, dur: secPerBeat, slideFrom: nil))) }
                                } else {
                                    let f = c.notes.suffix(3)[c.notes.count - 3 + (b % 3)]
                                    out.append(.init(at: x, kind: .tone(.piano, freq: f, amp: 0.13, dur: secPerBeat * 0.8, slideFrom: nil)))
                                }
                            default:
                                if b == 0 {
                                    for (k, f) in c.notes.enumerated() { out.append(.init(at: x + k * Int(rate * 0.014), kind: .pluck(freq: f, amp: 0.3, decay: 0.996))) }
                                } else {
                                    for (k, f) in c.notes.suffix(2).enumerated() { out.append(.init(at: x + k * Int(rate * 0.02), kind: .pluck(freq: f, amp: 0.2, decay: 0.995))) }
                                }
                            }
                        }
                    }
                    t += c.beats
                }
            case .bass:
                var t = 0.0
                for c in chords {
                    if let root = c.notes.first {
                        for b in stride(from: 0.0, to: c.beats, by: Double(song.meter == 3 ? 3 : 2)) {
                            out.append(.init(at: at(t + b), kind: .pluck(freq: root / 2, amp: 0.55, decay: 0.997)))
                        }
                    }
                    t += c.beats
                }
            case .drums:
                let total = melody.reduce(0) { $0 + $1.beats }
                var b = 0.0
                while b < total - 0.01 {
                    let inBar = b.truncatingRemainder(dividingBy: Double(song.meter))
                    let onBeat = abs(inBar.rounded() - inBar) < 0.01
                    if onBeat {
                        let i = Int(inBar.rounded())
                        if song.meter == 3 {
                            out.append(.init(at: at(b), kind: .drum(i == 0 ? .kick : .snare, amp: i == 0 ? 0.9 : 0.25)))
                        } else {
                            out.append(.init(at: at(b), kind: .drum(i % 2 == 0 ? .kick : .snare, amp: i % 2 == 0 ? 0.9 : 0.4)))
                        }
                    }
                    out.append(.init(at: at(b), kind: .drum(.hat, amp: onBeat ? 0.35 : 0.22)))
                    b += 0.5
                }
                out.append(.init(at: at(total), kind: .drum(.kick, amp: 0.9)))
            }
        }
        return out
    }

    /// 二胡声部：一把弓连着拉。换弓规则（谱上没逐个标弓法时的常见拉法）：
    /// 一句开头、落在整拍上的音、一拍以上的长音、长音之后都换弓；倚音、滑音连着的音和半拍里的碎音在同一弓里
    static func erhuLine(_ melody: [Song.Note], beat: Double, octave: Double, levelScale: Double) -> [GuitarSynth.Event] {
        var out: [GuitarSynth.Event] = []
        var level = 0.64
        var t = 0.0
        // 先把休止以外的音连同开始拍位收集起来
        var items: [(at: Double, note: Song.Note, level: Double)] = []
        for n in melody {
            if let d = n.dyn { level = d; continue }
            items.append((t, n, level))
            t += n.beats
        }
        func midi(_ f: Double) -> Double { 69 + 12 * log2(f * octave / 440) }
        for (i, it) in items.enumerated() {
            guard let f = it.note.freq else { continue }
            let prev = i > 0 ? items[i - 1] : nil
            let next = i + 1 < items.count ? items[i + 1] : nil
            let flags = ErhuFlags(Substring(it.note.flags))
            let phraseStart = prev?.note.freq == nil
            let phraseEnd = next?.note.freq == nil
            let onBeat = abs(it.at - it.at.rounded()) < 0.001
            let prevLong = (prev?.note.beats ?? 0) >= 1
            let grace = it.note.beats < 0.1 || (prev.map { $0.note.beats < 0.1 } ?? false)
            let slid = prev.map { ErhuFlags(Substring($0.note.flags)).contains(.glide) } ?? false
            let bow = !phraseStart && !grace && !slid && (onBeat || it.note.beats >= 1 || prevLong)
            let e = ErhuNote(midi: midi(f), length: Int(it.note.beats * beat), flags: flags, level: it.level * levelScale,
                             nextMidi: next?.note.freq.map(midi), bowChange: bow, phraseStart: phraseStart, phraseEnd: phraseEnd)
            out.append(.init(at: Int(it.at * beat), kind: .erhu(e)))
        }
        return out
    }
}
