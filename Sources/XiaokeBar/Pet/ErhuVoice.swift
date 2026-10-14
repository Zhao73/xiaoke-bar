import Foundation

/// 二胡的一个音（编排时就算好前后关系：要不要换弓、往哪个音滑、是不是一句的结尾）
struct ErhuNote: Sendable {
    var midi: Double
    var length: Int              // 采样数
    var flags: ErhuFlags
    var level: Double            // 力度（pp 0.25 … ff 1）
    var nextMidi: Double?        // 后面紧跟的音（中间没有休止）
    var bowChange: Bool          // 这个音开始时换弓
    var phraseStart: Bool        // 前面是休止 / 开头
    var phraseEnd: Bool          // 后面是休止 / 结尾
}

struct ErhuFlags: OptionSet, Sendable {
    let rawValue: Int
    static let glide = ErhuFlags(rawValue: 1)     // ~  这个音的尾巴滑到下一个音（谱上的 ↘ ↗ 箭头）
    static let scoop = ErhuFlags(rawValue: 2)     // /  从下面滑进这个音
    static let trill = ErhuFlags(rawValue: 4)     // t  颤音（和上方大二度快速交替）
    static let tremolo = ErhuFlags(rawValue: 8)   // *  颤弓（快速来回拉）
    static let accent = ErhuFlags(rawValue: 16)   // >  重音
    static let breath = ErhuFlags(rawValue: 32)   // ,  音尾断一下再换弓

    init(rawValue: Int) { self.rawValue = rawValue }
    init(_ s: Substring) {
        var f: ErhuFlags = []
        for c in s {
            switch c {
            case "~": f.insert(.glide); case "/": f.insert(.scoop); case "t": f.insert(.trill)
            case "*": f.insert(.tremolo); case ">": f.insert(.accent); case ",": f.insert(.breath)
            default: break
            }
        }
        self = f
    }
}

/// 二胡发声器：单音、连奏，一把弓一根弦。参数按真实二胡录音量出来的数据调：
/// - 弦：弓拉弦是锯齿状的「粘-滑」振动，泛音约按 1/n 衰减；弓位离琴码很近，按得越高弓位比例越大，泛音上会出现梳状凹口
/// - 弓毛擦弦的沙沙声：每个振动周期「滑」的那一下最响（和音高同步的噪声），换弓时更明显
/// - 揉弦约 5 Hz、±35–45 音分，音出来约 0.15 秒后才揉起来；颤弓每秒约 12 下、音量起伏约 9 dB
/// - 琴筒蟒皮共鸣：350–600 Hz 主峰、800–900 Hz 凹陷、1.4–1.6 kHz 鼻音峰、2 kHz 以上陡降（三分之一倍频程均衡器拟合）
/// - 最后加一点短混响，不然干巴巴的像电子琴
struct ErhuVoice {
    let rate: Double
    private var note: ErhuNote?
    private var tau = 0                         // 当前音已经响了多少采样
    private var prevMidi: Double?
    private var pitch: Double = 55              // 平滑后的实际音高（midi，带小数）
    private var phase: Double = 0               // 0..1
    private var amp: Double = 0                 // 平滑后的音量
    private var level: Double = 0.6             // 平滑后的力度
    private var vibPhase: Double = 0
    private var vibRate: Double = 5
    private var jitter: Double = 0
    private var noiseLP: Double = 0
    private var noiseHP: Double = 0
    private var burst: Double = 0               // 换弓时的擦弦声
    private var weights = [Double](repeating: 0, count: 48)
    private var nHarm = 0
    private var ctl = 0
    private var target = (pitch: 55.0, amp: 0.0, noise: 0.0)
    private var eq: [Biquad]
    private var reverb = Reverb()
    private var rng = SplitMix(seed: 0x5EED)
    private(set) var silent = true

    init(rate: Double) {
        self.rate = rate
        eq = ErhuVoice.bodyEQ(rate: rate)
    }

    /// 琴筒共鸣：高通 + 一组三分之一倍频程峰值滤波 + 低通。增益是拿两段真实二胡录音（Wikimedia Commons 上张培坚演奏的
    /// 《二泉映月》《江河水》）的谐波包络和本合成器的输出反复比对拟合的，300–6000 Hz 平均误差约 3 dB。
    /// 低频切得很狠是真实情况：二胡琴筒小，低音的基音很弱，主要靠 2、3 次泛音发声
    static let eqBands: [(f: Double, gain: Double)] = [
        (160, -20), (200, -26), (250, -18), (315, -9), (400, 4), (500, 1), (630, -2), (800, -12), (1000, 0),
        (1250, 0), (1600, 14), (2000, -9), (2500, -8), (3150, -5), (4000, 0), (5000, -6), (6300, -7), (8000, -8),
    ]

    /// 弓噪的总量（调参：XIAOKE_ERHU_NOISE 临时覆盖）
    static let noiseGain: Double = ProcessInfo.processInfo.environment["XIAOKE_ERHU_NOISE"].flatMap(Double.init) ?? 2.5

    static func bodyEQ(rate: Double) -> [Biquad] {
        var bands = eqBands
        // 调参用：XIAOKE_ERHU_EQ="160:-6,200:-8,..." 临时覆盖，不用重新编译
        if let env = ProcessInfo.processInfo.environment["XIAOKE_ERHU_EQ"] {
            bands = env.split(separator: ",").compactMap { p in
                let kv = p.split(separator: ":").compactMap { Double($0) }
                return kv.count == 2 ? (kv[0], kv[1]) : nil
            }
        }
        var list = [Biquad.highpass(f: 150, q: 0.7, rate: rate)]
        for b in bands { list.append(.peaking(f: b.f, gain: b.gain, q: 4.3, rate: rate)) }
        list.append(.lowpass(f: 9000, q: 0.7, rate: rate))
        return list
    }

    mutating func start(_ n: ErhuNote) {
        if let cur = note { prevMidi = cur.midi }
        if n.phraseStart { prevMidi = nil; pitch = n.midi - (n.flags.contains(.scoop) ? 1.5 : 0.25) }
        note = n
        tau = 0
        if n.bowChange || n.phraseStart { burst = n.phraseStart ? 0.6 : 0.45 }
        if n.flags.contains(.accent) { burst = max(burst, 0.7) }
        silent = false
        ctl = 0
    }

    /// 停下：当前这个音 0.15 秒内收弓
    mutating func release() {
        guard var n = note else { return }
        n.phraseEnd = true
        n.nextMidi = nil
        n.length = min(n.length, tau + Int(rate * 0.15))
        note = n
    }

    private static func smooth(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }

    /// 每 16 个采样算一次「该在哪个音高、多大声」
    private mutating func control() {
        guard let n = note else { target = (pitch, 0, 0); return }
        let t = Double(tau) / rate
        let dur = Double(n.length) / rate
        var p = n.midi

        // 从下面滑进来（谱上音前的 ↗）
        if n.flags.contains(.scoop) { p -= 1.5 * (1 - Self.smooth(t / 0.16)) }
        // 尾巴滑到下一个音（谱上的 ↘ / ↗）：占音的后 45%，最长 0.32 秒
        if n.flags.contains(.glide), let next = n.nextMidi {
            let g = min(0.32, dur * 0.45)
            if t > dur - g { p += (next - n.midi) * Self.smooth((t - (dur - g)) / g) }
        }
        // 颤音：和上方大二度来回打，每秒 9 下
        if n.flags.contains(.trill), t > 0.03, t < dur - 0.04 {
            if Int((t - 0.03) * 18) % 2 == 0 { p += 2 }
        }
        // 揉弦：出声约 0.15 秒后慢慢加深，短音几乎不揉
        let full = n.flags.contains(.tremolo) ? 0.1 : 0.55 * min(1, max(0, (dur - 0.18) / 0.45))
        let depth = full * Self.smooth((t - 0.13) / 0.32)
        p += depth * sin(vibPhase * 2 * .pi)
        p += jitter

        // 音量：力度 × 弓的包络
        var a = 1.0
        if n.phraseStart { a *= Self.smooth(t / 0.12) }                                   // 一句开头慢慢拉出来
        else if n.bowChange { a *= 0.45 + 0.55 * Self.smooth(t / 0.07) }                  // 换弓的一下小凹陷
        let tail = dur - t
        if n.phraseEnd { a *= Self.smooth(tail / min(0.16, dur * 0.35)) }                 // 一句结尾收弓
        if n.flags.contains(.breath) { a *= Self.smooth((tail - 0.14) / 0.18) }           // 换气：收弓后留一小段空
        if dur > 0.9 { a *= 0.86 + 0.14 * sin(.pi * min(1, t / dur)) }                    // 长音中间略鼓起来
        if n.flags.contains(.accent) { a *= 1 + 0.35 * exp(-t / 0.1) }
        if n.flags.contains(.tremolo) {
            // 颤弓：每秒 12 下来回，每一下都是一次小换弓
            let c = 0.5 + 0.5 * cos(2 * .pi * 12 * t)
            a *= 0.3 + 0.7 * (1 - c * c)
            if c > 0.97 { burst = max(burst, 0.25) }
        }
        a *= 1 + 0.05 * sin(vibPhase * 2 * .pi) * (depth / 0.55)                          // 揉弦带一点音量起伏

        target = (p, a, Self.noiseGain * (0.035 + 0.06 * (1 - min(1, n.level))))
    }

    mutating func next() -> Float {
        if silent { return 0 }
        if ctl == 0 {
            control()
            // 弓位：按得越高（弦越短），弓离琴码的比例越大
            let f = 440 * pow(2, (pitch - 69) / 12)
            let beta = min(0.22, 0.055 * f / 196)
            nHarm = min(weights.count, Int(9000 / f))
            for k in 1...max(1, nHarm) {
                let x = Double(k) * .pi * beta
                let comb = max(0.14, abs(sin(x) / x))
                weights[k - 1] = comb / Double(k)
            }
            // 慢慢漂移的揉弦速度和音高微抖
            vibRate += (5 + rng.signed() * 0.35 - vibRate) * 0.02
            jitter += (rng.signed() * 0.07 - jitter) * 0.1
        }
        ctl = (ctl + 1) % 16

        let dt = 1 / rate
        // 手指在弦上移动不是瞬间的：音高跟目标之间有约 12 毫秒的平滑（换音时自然带一点滑）
        pitch += (target.pitch - pitch) * (1 - exp(-dt / 0.012))
        amp += (target.amp - amp) * (1 - exp(-dt / 0.008))
        if let n = note { level += (n.level - level) * (1 - exp(-dt / 0.5)) }
        vibPhase += vibRate * dt
        if vibPhase > 1 { vibPhase -= 1 }

        let f = 440 * pow(2, (pitch - 69) / 12)
        phase += f * dt
        if phase >= 1 { phase -= 1 }

        // 锯齿状的弦振动：用递推一次算出所有 sin(kφ)，每个采样只要一次 sin 和 cos
        let w = 2 * .pi * phase
        let c2 = 2 * cos(w)
        var s1 = sin(w), s0 = 0.0, sum = 0.0
        for k in 0..<nHarm {
            sum += weights[k] * s1
            let s2 = c2 * s1 - s0
            s0 = s1; s1 = s2
        }

        // 弓毛擦弦声：每个周期「滑」的那一瞬最响 + 一点持续的沙沙声，先高通掉低频
        let d = min(phase, 1 - phase)
        let pulse = exp(-d * d / (2 * 0.05 * 0.05))
        let white = rng.signed()
        noiseLP += (white - noiseLP) * 0.25
        // 高通掉低频再低通掉嘶声：擦弦声主要落在 1–2 kHz
        noiseHP += (white - noiseLP - noiseHP) * 0.3
        burst *= exp(-dt / 0.045)
        let noise = noiseHP * (target.noise * (0.4 + 1.6 * pulse) + burst * 0.5)

        var x = (sum * 0.9 + noise) * amp
        for i in eq.indices { x = eq[i].process(x) }
        x *= level * 0.65

        let wet = reverb.process(x)
        let out = x + wet * 0.2

        tau += 1
        if let n = note, tau >= n.length, n.phraseEnd || n.nextMidi == nil {
            note = nil
            target.amp = 0
        }
        if note == nil, amp < 1e-4, abs(wet) < 1e-5 { silent = true; amp = 0 }
        return Float(out)
    }
}

/// 标准 RBJ 双二阶滤波器
struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = 0.0, z2 = 0.0

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    private static func make(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func peaking(f: Double, gain: Double, q: Double, rate: Double) -> Biquad {
        let A = pow(10, gain / 40), w = 2 * .pi * f / rate, al = sin(w) / (2 * q), c = cos(w)
        return make(1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A)
    }

    static func highpass(f: Double, q: Double, rate: Double) -> Biquad {
        let w = 2 * .pi * f / rate, al = sin(w) / (2 * q), c = cos(w)
        return make((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
    }

    static func lowpass(f: Double, q: Double, rate: Double) -> Biquad {
        let w = 2 * .pi * f / rate, al = sin(w) / (2 * q), c = cos(w)
        return make((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
    }
}

/// 小房间混响（Freeverb 的简化版：4 个梳状 + 2 个全通）
struct Reverb {
    private var combs: [(buf: [Double], i: Int, store: Double)] = [1116, 1188, 1277, 1356].map { ([Double](repeating: 0, count: $0), 0, 0) }
    private var aps: [(buf: [Double], i: Int)] = [556, 441].map { ([Double](repeating: 0, count: $0), 0) }

    mutating func process(_ x: Double) -> Double {
        var out = 0.0
        for k in combs.indices {
            let y = combs[k].buf[combs[k].i]
            combs[k].store = y * 0.7 + combs[k].store * 0.3          // 高频衰减得快一点
            combs[k].buf[combs[k].i] = x + combs[k].store * 0.8
            combs[k].i = (combs[k].i + 1) % combs[k].buf.count
            out += y
        }
        out *= 0.25
        for k in aps.indices {
            let b = aps[k].buf[aps[k].i]
            let y = -out + b
            aps[k].buf[aps[k].i] = out + b * 0.5
            aps[k].i = (aps[k].i + 1) % aps[k].buf.count
            out = y
        }
        return out
    }
}

/// 很快的伪随机数（音频线程里不能用系统随机数，太慢还可能加锁）
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func signed() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 52) - 1
    }
}
