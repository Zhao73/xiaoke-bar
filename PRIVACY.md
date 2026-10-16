# Privacy Policy — Xiaoke Bar

_Last updated: October 16, 2026_

This policy covers Xiaoke Bar for Mac (the App Store build and the build on the GitHub releases page) and its iPhone companion app.

## The short version

- **We collect nothing.** There is no account, no analytics, no tracking and no advertising.
- If you pair the iPhone app with a QR code, the two devices talk through a small relay server that only passes along **end-to-end encrypted** data it cannot read (see below). Nothing else goes through a developer server.
- Everything the app shows is read on **your own Mac**, from files and credentials that your AI coding tools already keep there.
- The only network requests go **directly from your Mac to the official services of the tools you use**, with your own credentials.

## What the Mac app reads

With your permission (macOS asks you to grant access to your home folder once), the app reads:

- Session logs of AI coding tools in folders such as `~/.claude`, `~/.codex`, `~/.gemini` and `~/.grok`, to count tokens and list your sessions.
- The login credentials these tools stored in your macOS Keychain (only if you install the optional helper script), to ask their official usage endpoints how much quota is left.
- A list of running processes, to show which AI sessions are running right now.
- CPU, memory and disk usage, to show the system meters and resource alerts.

This data stays on your Mac. It is not uploaded anywhere by us.

## Network requests

To show quota and billing, the app sends requests only to the official endpoints of the services you use, for example `api.anthropic.com`, `chatgpt.com`, `cloudcode-pa.googleapis.com` and `grok.com`, and to API providers whose keys you add yourself. These requests carry your own credentials, exactly as the tools themselves do. Those services handle the requests under their own privacy policies.

API keys you add in the app are stored only in your macOS Keychain.

## iPhone companion app and iCloud

If you use the iPhone app, the Mac app stores a small snapshot (remaining quota, running session titles, token totals), your remote commands and scheduled messages in **your own private iCloud database** (CloudKit). While you have a session's terminal open on your iPhone, the Mac also stores the last part of that terminal's text there, refreshed every few seconds, and stops when you close it. Typing into a terminal from the iPhone is off until you turn it on in the Mac app. Only devices signed in to your Apple Account can read this data. The developer cannot access it.

Widgets and the Live Activity on your iPhone show a copy of the latest snapshot that is kept on the device.

## Live relay (QR-code pairing)

Instead of, or as well as, iCloud, you can pair the iPhone with the Mac by scanning a QR code shown in the Mac app. This is how the Mac build from the GitHub releases page connects to the iPhone, and it is faster (typing reaches the terminal in a fraction of a second).

- The QR code contains a random room ID and a random 256-bit key. It is created on your Mac and never sent to us.
- The Mac and iPhone encrypt every record (the same snapshot, commands, scheduled messages and terminal text described above) with that key using ChaCha20-Poly1305 **before** it leaves the device. The relay server (run by the developer on Cloudflare) stores and forwards only the room ID, record names and the encrypted bytes. It cannot read or change the content.
- Deleted records are fully removed from the relay after two days, and a room that no device has connected to for 30 days is erased.
- Tapping "New code" in the Mac app, or "Disconnect" on the iPhone, stops that pairing. Anyone who has the QR code can read that Mac's synced data, so do not share it.
- Like any web server, Cloudflare may process connection metadata such as IP addresses to deliver the service. We do not log or analyse it.

## Purchases

Purchases are processed by Apple. We do not receive your payment details.

## Children

The app is a developer tool and is not directed at children.

## Changes and contact

If this policy changes, the new version will be published at this address with a new date.
Questions: open an issue at <https://github.com/Zhao73/xiaoke-bar/issues>.

---

## 隐私政策（简体中文）

- **我们不收集任何数据**：没有账号、没有统计分析、没有追踪和广告，也没有开发者服务器。
- App 显示的内容全部在**你自己的 Mac 上**读取：AI 编程工具的会话记录（如 `~/.claude`、`~/.codex`）、它们存在钥匙串里的登录信息（仅在安装可选的增强组件后）、正在运行的进程、CPU/内存/磁盘用量。
- 联网只发生在**你的 Mac 和你所用工具的官方接口之间**（如 `api.anthropic.com`、`chatgpt.com`），使用的是你自己的凭证。你添加的 API Key 只存在钥匙串里。
- 扫码配对（GitHub 发布页下载的版本也能用）时，两台设备经开发者在 Cloudflare 上运行的中转服务器传数据：每条内容离开设备前就用二维码里的 256 位密钥加密（ChaCha20-Poly1305），服务器只看得到房间号、记录名和密文，读不到也改不了内容；删除的记录两天后彻底清除，30 天没有设备连接的房间整个删除。不要把二维码发给别人。
- 使用 iPhone App 时，额度快照、远程指令和定时发送存在**你自己的私有 iCloud**（CloudKit）里；在 iPhone 上打开某个会话的终端时，Mac 会把这个终端最近的文字每几秒同步一次，关掉就停止。从 iPhone 往终端输入默认关闭，需要在 Mac 上手动打开。开发者无法访问这些数据。
- GitHub 发布页版本的「远程终端」：在 iPhone 上新建终端时，Mac 会开一个你自己的 shell，把它的输出加密后经中转实时发给 iPhone，iPhone 的按键也同样加密发回；这些实时消息服务器只转发、不保存。
- 购买由 Apple 处理，我们拿不到你的付款信息。
- 联系方式：<https://github.com/Zhao73/xiaoke-bar/issues>

## プライバシーポリシー（日本語）

- **データは一切収集しません。** アカウント、解析、トラッキング、広告、開発者のサーバーはありません。
- 表示する情報はすべて**あなたの Mac 上で**読み取ります：AI コーディングツールのセッション記録（`~/.claude`、`~/.codex` など）、キーチェーンに保存されたログイン情報（任意のヘルパーをインストールした場合のみ）、実行中のプロセス、CPU・メモリ・ディスクの使用量。
- 通信は**あなたの Mac と各ツールの公式エンドポイントの間だけ**（`api.anthropic.com`、`chatgpt.com` など）で、あなた自身の認証情報を使います。追加した API キーはキーチェーンにのみ保存されます。
- QR コードでペアリングした場合（GitHub 配布版も対応）、2台のデバイスは開発者が Cloudflare 上で運用する中継サーバーを経由します。各データは端末を出る前に QR コード内の 256 ビット鍵で暗号化（ChaCha20-Poly1305）され、サーバーが扱うのはルーム ID・レコード名・暗号文だけで、内容を読むことも改ざんすることもできません。削除したデータは2日後に完全に消え、30 日間どのデバイスも接続しないルームは丸ごと削除されます。QR コードは他人に見せないでください。
- iPhone アプリを使う場合、使用量のスナップショット、リモート操作、予約送信は**あなた自身のプライベートな iCloud**（CloudKit）に保存されます。iPhone でセッションのターミナルを開いている間は、そのターミナルの直近のテキストも数秒ごとに同期され、閉じると止まります。iPhone からの入力は Mac 側でオンにするまで無効です。開発者はアクセスできません。
- 購入は Apple が処理し、支払い情報を受け取ることはありません。
- お問い合わせ：<https://github.com/Zhao73/xiaoke-bar/issues>

## 개인정보 처리방침（한국어）

- **어떤 데이터도 수집하지 않습니다.** 계정, 분석, 추적, 광고, 개발자 서버가 없습니다.
- 표시되는 정보는 모두 **사용자의 Mac에서** 읽습니다: AI 코딩 도구의 세션 기록(`~/.claude`, `~/.codex` 등), 키체인에 저장된 로그인 정보(선택 사항인 헬퍼를 설치한 경우에만), 실행 중인 프로세스, CPU·메모리·디스크 사용량.
- 네트워크 요청은 **사용자의 Mac과 각 도구의 공식 엔드포인트 사이에서만**(`api.anthropic.com`, `chatgpt.com` 등) 사용자 본인의 인증 정보로 이루어집니다. 추가한 API 키는 키체인에만 저장됩니다.
- QR 코드로 페어링하면(GitHub 배포 버전도 지원) 두 기기는 개발자가 Cloudflare에서 운영하는 중계 서버를 거칩니다. 모든 데이터는 기기를 떠나기 전에 QR 코드 속 256비트 키로 암호화(ChaCha20-Poly1305)되며, 서버는 방 ID·레코드 이름·암호문만 다루고 내용을 읽거나 바꿀 수 없습니다. 삭제된 데이터는 2일 후 완전히 지워지고, 30일 동안 아무 기기도 연결하지 않은 방은 통째로 삭제됩니다. QR 코드를 다른 사람에게 보내지 마세요.
- iPhone 앱을 사용하면 사용량 스냅샷, 원격 명령, 예약 메시지는 **사용자 본인의 비공개 iCloud**(CloudKit)에 저장됩니다. iPhone에서 세션의 터미널을 열어 두는 동안에는 그 터미널의 최근 텍스트도 몇 초마다 동기화되며, 닫으면 멈춥니다. iPhone에서 입력하는 기능은 Mac에서 켜기 전까지 꺼져 있습니다. 개발자는 접근할 수 없습니다.
- 결제는 Apple이 처리하며 결제 정보를 받지 않습니다.
- 문의: <https://github.com/Zhao73/xiaoke-bar/issues>
