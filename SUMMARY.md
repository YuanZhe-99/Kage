# Project: GhostCursor / ContextHelper
## macOS 隐蔽远程桌面与自动化控制架构设计

> **伪装定位**: 一款本地 AI 助手（类似 ChatGPT Desktop），提供悬浮窗问答与上下文辅助功能。远程控制模块作为其隐藏能力，仅在持有密钥的 P2P 对端连接时激活。

---

## 1. 核心设计哲学

1. **最小权限原则 (Least Privilege)**
   - **绝对不请求管理员权限**：不写 `/Library`、`/System`，不安装 Kernel Extension / Driver Extension / System Extension。
   - **仅请求两项用户级权限**：
     - **屏幕录制** (`kTCCServiceScreenCapture`)：仅用于被控端画面回传。
     - **辅助功能** (`kTCCServiceAccessibility`)：仅用于模拟键盘/语义化点击（不移动物理光标）。
   - 无麦克风、无摄像头、无全盘磁盘访问权限请求。

2. **深度伪装 (Plausible Deniability)**
   - **UI 伪装**：主界面为 SwiftUI 构建的 AI 聊天悬浮窗，支持真正的 LLM API 调用（如 OpenAI/Claude），作为正常功能使用。
   - **进程伪装**：Bundle ID 为 `com.[developer].contexthelper`，进程名 `ContextHelper`，Dock 无图标，仅菜单栏常驻一个“灯泡/星星”图标。
   - **网络伪装**：信令流量伪装成标准 HTTPS/JSON SSE（OpenAI API 格式），支持 HTTP/2 或 HTTP/3 (QUIC)；P2P 数据为加密 UDP，无传统远程桌面特征端口（如 5900）。
   - **文件系统伪装**：数据仅写入 `~/Library/Application Support/ContextHelper/`。

3. **服务器作为发现与身份基础设施**
   - **非可选组件**：无论是否启用 TURN Relay，中央服务器都是 P2P 通信的必要前提。在没有公网 IP 和内网发现机制的情况下，双方必须依赖服务器交换网络位置（ICE Candidates）与身份公钥，否则无法知道对方“在哪里”。
   - **最小化信任**：服务器**仅负责发现、信令转发与公钥托管**，绝不触碰加密后的媒体数据或会话内容。所有 Payload 在离开客户端前已由 ed25519 + ChaCha20-Poly1305 加密。
   - **单向密钥持有**：受控端仅持久保存自己的 ed25519 **公钥**；对应的**私钥仅提供一次下载**（首次配对时由控制端生成并保存），不在受控端本地留存，支持随时重置。

4. **无物理光标入侵 (Background Input)**
   - **不调用 `CGEventPost` 移动全局鼠标**，避免本地用户看到光标被远程“抢走”。
   - 鼠标操作通过 **Accessibility API (AXUI)** 在语义层完成（查找元素 -> 聚焦 -> 执行 Action）。
   - 键盘操作通过 `CGEvent` Post 到会话层，不涉及光标位移。
   - 如果本地用户正在打字/移动鼠标，远程操作在后台静默执行，互不阻塞（除目标窗口焦点可能切换外）。

---

## 2. 技术栈

| 层级 | 技术选型 | 理由 |
|------|----------|------|
| **语言** | Swift (被控端), Swift / TypeScript (控制端) | 原生 macOS API 调用最便捷，二进制特征自然 |
| **UI** | SwiftUI + AppKit (MenuBarExtra) | 构建 ChatGPT-like 悬浮窗与菜单栏图标 |
| **P2P/网络** | `libdatachannel` (C++ wrapper) | 仅启用 DataChannel + ICE/DTLS，不引入完整 WebRTC 媒体栈，二进制更小、特征更弱 |
| **视频捕获** | `ScreenCaptureKit` (SCStream) | macOS 12.3+ 官方推荐，硬件加速，帧率高，功耗低 |
| **视频编码** | `VideoToolbox` (VTCompressionSession, H.264 / HEVC) | 纯用户空间硬编码，Apple Silicon & Intel 均支持硬件加速；HEVC 在相同画质下比 H.264 节省约 40% 带宽 |
| **输入控制** | `ApplicationServices` / `AXUIElement` | 语义化操作，避免 HID 注入 |
| **信令** | 自建 lightweight HTTPS server (Go/Node.js) | 接口伪装成 `/v1/chat/completions` SSE 流；支持 HTTP/2 (TCP) 与 HTTP/3 (QUIC/UDP) |
| **序列化** | MessagePack | 比 Protobuf 更轻，无 schema 文件依赖，天然二进制 |
| **密码学** | `libsodium` (Swift: `Swift-Sodium`, Go: `golang.org/x/crypto`) | 成熟的 ed25519 / X25519 / ChaCha20-Poly1305 / Argon2 实现，绝不自行造轮子 |

---

## 3. 系统架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             控制端 (Controller)                              │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐              │
│  │   视频解码    │◄─────│  DataChannel │◄─────│ ICE/DTLS     │◄── Internet  │
│  │ (VideoToolbox)│      │(libdatachannel)│    │ P2P UDP /    │              │
│  └──────────────┘      └──────────────┘      │ TURN Relay   │              │
│                                              └──────────────┘              │
│  ┌──────────────┐      ┌──────────────┐                                    │
│  │  本地输入捕获  │─────►│  输入编码封装  │                                    │
│  │ (NSEvent/CG)  │      │ (MessagePack) │                                    │
│  └──────────────┘      └──────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ 加密 UDP (P2P)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              被控端 (Agent)                                  │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐              │
│  │ ScreenCapture│─────►│  视频编码     │─────►│  DataChannel │──────┐       │
│  │    Kit       │      │(VideoToolbox)│      │(libdatachannel)│     │       │
│  └──────────────┘      └──────────────┘      └──────────────┘     │       │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐     │       │
│  │   AXUI 控制   │◄─────│  输入解码     │◄─────│ ICE/DTLS     │◄────┘       │
│  │ (无物理光标)  │      │ (MessagePack)│      │ P2P UDP /    │             │
│  └──────────────┘      └──────────────┘      │ TURN Relay   │             │
│                                              └──────────────┘             │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────┐          │
│  │         SwiftUI 主界面 (伪装层: AI Chat 悬浮窗)               │          │
│  └──────────────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ HTTPS + SSE (信令, 首次握手)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        中央发现与信令服务 (Signaling)                         │
│   Endpoint: `POST /v1/chat/completions` (伪装成 OpenAI API SSE 流)           │
│   传输: HTTP/2 (TCP 443) 或 HTTP/3 (QUIC/UDP 443)                            │
│   职责:                                                              │
│     1. 设备发现：维护受控端 UUID ↔ 当前网络坐标映射                          │
│     2. 信令交换：转发加密后的 SDP / ICE Candidate（服务器无法解密内容）       │
│     3. 公钥托管：存储受控端 ed25519 公钥，供控制端验证身份                     │
│     4. 绝不转发媒体：所有视频/输入数据走 P2P/TURN，不经过此服务器             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. 关键模块详解

### 4.1 P2P 网络层 (libdatachannel + Easytier 打洞策略 + 服务器发现)

- **为什么不用完整 WebRTC？**
  - 传统 libwebrtc 体积巨大（> 50MB），二进制中包含大量字符串特征（如 `WebRTC`, `SRTP`, `RTP`），易被静态分析识别。
  - `libdatachannel` 仅实现 ICE + DTLS + SCTP，无媒体引擎，可将视频帧作为二进制消息直接通过 DataChannel 发送，流量特征完全自定义。

- **服务器的核心作用：发现与信令，非可选**
  - 在典型的校园网/家庭 NAT 环境中，两端都没有公网 IP，也缺乏 mDNS/局域网发现条件。**中央服务器是 P2P 握手的前置必要条件**，其职责包括：
    1. **设备注册**：受控端上线时向服务器注册自己的 UUID 与当前网络坐标（IP、NAT 类型）。
    2. **信令中继**：控制端查询目标 UUID 后，服务器将双方的加密 SDP / ICE Candidate 互相转发。Payload 由客户端 ed25519 公钥加密，服务器仅做透传。
    3. **TURN 地址下发**：若启用 Relay 模式，服务器同时下发 TURN 服务器地址与临时凭证。
  - **明确边界**：服务器**不参与也不转发**任何视频流或输入指令；P2P/TURN 链路建立后，客户端与服务器之间除心跳外无持续长连接。

- **身份与密钥体系 (ed25519)**
  - **密钥生成**：使用 `libsodium` 生成 ed25519 密钥对。
  - **受控端策略**：
    - 首次启动生成 ed25519 密钥对，**仅将公钥上传至服务器持久化**；**私钥立即丢弃，不在本地磁盘或 Keychain 中留存**。
    - 控制端首次配对时，通过服务器获取受控端公钥，并自行生成一对 ed25519 密钥用于本次会话；控制端持有自己的私钥，受控端永不持有任何长期私钥。
    - 若需要重置身份（如怀疑密钥泄露），受控端可重新生成密钥对，旧公钥在服务器上标记为过期。
  - **控制端策略**：
    - 控制端在本地 Keychain / Secure Enclave 中保存自己的长期 ed25519 私钥。
    - 连接前，通过服务器查询受控端公钥，验证信令 Payload 的签名，防止中间人篡改 SDP。
  - **会话密钥派生**：P2P 握手成功后，双方通过 X25519 ECDH 交换临时密钥，结合 PSK 使用 `libsodium` 的 `crypto_kdf_derive_from_key` 派生 DataChannel 的对称会话密钥 (ChaCha20-Poly1305)。

- **受控端 UUID 生成策略**
  - 首次启动时，基于机器指纹生成确定性 UUID：
    ```
    uuid = UUIDv5(namespace, SHA256(MAC地址 + 主板SN + 系统序列号 + 安装时间盐值))
    ```
  - **理由**：MAC 地址与 SN 号具有硬件唯一性，确保即使重装 App，同一台机器仍能被识别为同一个受控端；盐值防止彩虹表反向推导。
  - **隐私保护**：UUID 与硬件信息均为本地计算，仅上传最终 UUID 与公钥，不上传原始 MAC/SN。

- **NAT 穿透：参考 Easytier 的多层打洞策略**
  - Easytier 是一款国产开源 P2P VPN，其在复杂 NAT（含对称 NAT）环境下的打洞成功率极高，核心策略可迁移到本方案：
    1. **多端 STUN 探测**：不依赖单一 STUN，同时向多个公共 STUN / 私有 STUN 发送 Binding Request，综合判断 NAT 类型（Full Cone、Restricted Cone、Port Restricted、Symmetric）。
    2. **端口预测与生日攻击 (Birthday Attack)**：若检测为对称 NAT，根据已观测到的端口分配规律（如递增、固定偏移）预测下一次外部端口，在候选端口范围内快速发送多个 UDP 探测包（生日悖论原理提升碰撞概率），增加打洞成功率。
    3. **IPv6 优先**：若双方任意一端具备公网 IPv6，直接通过 IPv6 建立 UDP 连接，完全绕过 NAT。
    4. **同时发起连接 (Simultaneous Open)**：信令交换完成后，双方立即同时向对方所有候选地址（Host / Server Reflexive / Relayed / Predicted）发送 DTLS Hello，利用防火墙状态表短暂开放窗口完成握手。
  - **libdatachannel 集成**：在现有 ICE Agent 中扩展 `trickle ICE` 逻辑，自定义 Gathering 阶段加入端口预测候选 (Peer Reflexive / Predicted)，而非仅依赖标准 STUN 返回的 Server Reflexive 地址。

- **传输模式：P2P 优先，TURN 作为优雅降级 (Fallback)**
  - **模式一：纯 P2P (Direct)**
    - 默认优先尝试所有候选地址直连。
    - 成功则流量完全不经第三方，延迟最低，且无任何中心化服务器中转痕迹。
  - **模式二：TURN 中继 (Relay)**
    - 当所有 P2P 候选均失败后（如双方均为对称 NAT + 无 IPv6），自动降级至 TURN 服务器中继。
    - **伪装策略**：TURN 服务器可部署在普通云主机上，监听 443/UDP 或 443/TCP，DTLS 外层流量与常规 HTTPS/QUIC 特征相似；TURN 凭证通过 PSK 派生，不单独分配用户账号。
    - **权限与隐私**：TURN 服务器仅作为无状态包转发层，无法解密 DTLS 内层数据；不记录元数据，定期轮换公网 IP 与端口。
  - **模式切换感知**：连接建立后，若检测到当前为 Relay 模式，控制端 UI 可显示一个 subtle 的链路状态指示（如一个灰色小圆点），提示用户当前非最优链路。

- **信令传输与伪装 (HTTP/2 & HTTP/3)**
  - **协议选择**：信令服务器同时监听 `TCP 443` (HTTP/2 + TLS) 与 `UDP 443` (HTTP/3 / QUIC)。客户端优先尝试 HTTP/3（QUIC 基于 UDP，与后续 P2P UDP 流量特征更一致，且连接建立更快）；若网络阻断 UDP 则自动回退至 HTTP/2 over TCP。
  - **流量伪装**：
    - 控制端向服务器发起 `POST /v1/chat/completions`，Body 伪装成 OpenAI API 格式：
      ```json
      {
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": "<base64_encrypted_sdp>"}],
        "stream": true
      }
      ```
    - 服务器返回 SSE 流，携带对端加密 SDP/ICE（含端口预测候选与 TURN 分配地址）。
    - 从流量侧观察，这完全是一次标准的 LLM API 调用，无远程桌面特征。

### 4.2 视频捕获与编码 (硬件加速与带宽优化)

#### 4.2.1 编码策略

- **ScreenCaptureKit 流程**
  1. 创建 `SCContentFilter` 选择 `SCDisplay`（全屏）或特定 `SCWindow`。
  2. 配置 `SCStreamConfiguration`：指定分辨率、帧率（默认 30fps，动态可调）、是否捕获光标（**选择不捕获**，因为本地光标不动，且避免暴露远程操作）。
  3. 通过 `SCStream` 回调获取 `CMSampleBuffer`（格式通常为 `BGRA` 或 `YUV`）。
  4. 送入 `VTCompressionSession`，**优先启用硬件加速**：
     - **HEVC (H.265) with Hardware Acceleration**：macOS 10.13+ 支持，Apple Silicon 上效率极高。相比 H.264，在同等画质（PSNR）下码率可降低 **30%–50%**。
     - **H.264 Hardware Baseline/Main Profile**：作为 Fallback，兼容控制端解码能力不足的终端。
  5. 编码后的 NAL Unit 按帧序号打包为 MessagePack，通过 DataChannel 发送。

#### 4.2.2 带宽自适应与帧间压缩

- **动态码率控制 (ABR)**
  - 监测 DataChannel 的 `bufferedAmount` 与 ACK 往返时延 (RTT)。
  - 若检测到拥塞，实时下调 `VTCompressionSession` 的 `kVTCompressionPropertyKey_AverageBitRate` 与 `kVTCompressionPropertyKey_DataRateLimits`。
  - 若网络空闲，逐步提升码率以换取画质。

- **帧率自适应**
  - 检测到画面内容静止（通过像素差异哈希或 SCStream 的 `contentChanged` 提示）时，主动降低帧率至 5fps 甚至 1fps，显著降低突发带宽。
  - 检测到快速滑动/视频播放时，提升至 30–60fps。

- **增量编码与关键帧策略**
  - 采用标准的 GOP (Group of Pictures) 结构：每 2 秒一个 I-Frame，其余为 P-Frame，减少冗余数据。
  - 控制端请求强制刷新时，被控端立即插入一个 I-Frame。

- **分辨率缩放**
  - 默认捕获 Retina 物理分辨率，但在编码前通过 `VTPixelTransferSession` 进行硬件缩放（如 2560×1440 → 1920×1080），进一步降低带宽。
  - 控制端可发送指令要求被控端切换捕获分辨率（如全屏 → 仅捕获前台窗口）。

#### 4.2.3 控制端显示与硬件解码

- 控制端接收 NAL，使用 `VTDecompressionSession` **硬件解码**为 `CVPixelBuffer`，直接渲染到 `MTKView` / `CAMetalLayer`。
- 若控制端运行在非 macOS 平台（如 Web），则降级为软件解码（WASM/OpenH264），并在信令阶段协商编码格式。

### 4.3 输入控制系统 (Ghost Input)

> **核心约束**：本地物理光标（Hardware Cursor）位置**绝对不变**，本地用户不会看到光标跳动。

#### 4.3.1 远程鼠标点击 (Stealth Click)

```swift
// 伪代码
func stealthClick(at remotePoint: CGPoint) {
    // 1. 获取目标位置的可访问元素
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    AXUIElementCopyElementAtPosition(systemWide, Float(remotePoint.x), Float(remotePoint.y), &element)

    guard let target = element else { return }

    // 2. 将焦点设到该元素（如果它是文本框等）
    AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)

    // 3. 执行 Press Action（相当于点击）
    AXUIElementPerformAction(target, kAXPressAction as CFString)

    // 4. 对于支持 ShowMenu 的元素，可模拟右键
    AXUIElementPerformAction(target, kAXShowMenuAction as CFString)
}
```

- **优点**：完全不移动物理光标，无 CGEvent 注入，Activity Monitor 看不到 `CGEventPost` 调用链。
- **局限**：
  - 依赖应用的 Accessibility 支持（原生 Cocoa/AppKit 应用支持良好，部分游戏/非标 UI 无法识别）。
  - **不支持拖拽 (Drag & Drop)**，因为无物理光标路径。
  - **不支持像素级精确操作**（如 Photoshop 精细绘图），适合后台管理、点击按钮、填写表单。

#### 4.3.2 远程键盘输入

```swift
func postKeyEvent(keyCode: CGKeyCode, down: Bool) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
    // Post到Annotated Session，不会触碰到鼠标位置
    event?.post(tap: .cghidEventTap) // 实际上键盘事件不影响光标
}
```

- 对于纯文本输入，可以构建 `CGEvent` 序列直接输入字符串。
- 若目标 App 支持 Accessibility，也可直接设置 `kAXValueAttribute`，连键盘事件都无需 Post，更 stealth。

#### 4.3.3 控制端光标显示

- 控制端屏幕上显示一个**软件渲染的远程光标**，位置由控制端本地鼠标坐标映射到远程分辨率。
- 被控端**不显示远程光标**，仅执行操作。这样本地屏幕干净无异常。

### 4.4 伪装层 UI (ChatGPT-like Shell)

- **主界面**：
  - 全局快捷键（如 `Cmd+Shift+Space`）唤起一个圆角悬浮窗，顶部有 AI 模型选择，中间为对话记录，底部为输入框。
  - 真正接入一个 LLM API Key，可正常使用，作为“烟雾弹”。
- **隐藏入口**：
  - 在设置页最底部，或连续按某个特定快捷键序列，解锁“远程协助”面板，输入 PSK (Pre-Shared Key) 后开启 Agent 监听。
- **菜单栏**：
  - 仅一个图标，点击展开最近 3 条 AI 对话摘要，看起来像正常的 AI 助手历史记录。

---

## 5. 安全与对抗分析

### 5.1 对抗学校/IT 审查

| 检测手段 | 应对策略 |
|----------|----------|
| **进程名黑名单** (TeamViewer, AnyDesk, ToDesk...) | 进程名为 `ContextHelper`，Bundle ID 为 `com.xxx.contexthelper`，不在任何黑名单中 |
| **网络端口/协议特征** | 无 5900, 5938 等端口；P2P UDP 流量为加密 DTLS，无 VNC/RDP 握手特征 |
| **静态代码签名扫描** | 不包含 `VNC`, `RDP`, `RemoteDesktop` 等字符串；使用 Swift + datachannel，符号表自然 |
| **运行时行为检测** | 不创建 Kernel Extension；辅助功能权限仅出现在 Accessibility 白名单中，与无数效率工具一致 |
| **Dock/菜单栏观察** | 无 Dock 图标，菜单栏图标为通用 AI 图标，Activity Monitor 中显示为普通 User App |

### 5.2 连接安全与密钥管理

- **身份验证 (ed25519 + PSK 双因子)**
  - **长期身份**：双方通过 ed25519 公私钥对确认设备身份。控制端验证受控端公钥签名，受控端验证控制端公钥签名，防止服务器或中间人篡改信令。
  - **会话认证**：P2P 握手阶段额外要求双方输入相同的 **PSK (Pre-Shared Key)**，用于 DTLS 指纹校验与 X25519 ECDH 密钥派生。即使公钥被泄露，没有 PSK 也无法建立有效会话。
- **前向安全 (Forward Secrecy)**
  - 每次连接生成临时的 X25519 密钥对与 ICE ufrag/pwd，会话结束后立即销毁。
  - 使用 `libsodium` 的 `crypto_kx_client_session_keys` / `crypto_kx_server_session_keys` 派生会话密钥，保证单次会话泄露不影响历史通信。
- **密钥生命周期**
  - 受控端不保存任何长期私钥；控制端私钥可存储在 macOS Secure Enclave 中（若硬件支持），防止提取。
  - 支持密钥重置：受控端在设置中可一键“重新生成身份”，旧公钥在服务器上标记失效，控制端需重新配对。
- **无持久后门**：不写入 LaunchAgent / LaunchDaemon，不随系统启动（除非用户手动在系统设置中添加）。

---

## 6. 目录结构规划

```
GhostCursor/
├── SUMMARY.md                  # 本文件：总体架构设计
├── README.md                   # 对外伪装："ContextHelper - 本地 AI 效率助手"
├── Agent/                      # macOS 被控端 (Swift Package)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── ContextHelperApp.swift      # @main 入口，MenuBarExtra
│   │   │   ├── ChatWindowView.swift        # 伪装 AI 聊天界面
│   │   │   └── SettingsView.swift          # 设置（含隐藏远程面板）
│   │   ├── Core/
│   │   │   ├── ScreenCapture.swift         # ScreenCaptureKit 封装
│   │   │   ├── VideoEncoder.swift          # VideoToolbox H.264 编码
│   │   │   ├── GhostInput.swift            # AXUI 语义输入（无物理光标）
│   │   │   └── Permissions.swift           # TCC 权限检查与引导
│   │   ├── Crypto/
│   │   │   ├── KeyManager.swift            # ed25519 密钥生成、Secure Enclave 存储、重置逻辑
│   │   │   ├── UUIDGenerator.swift         # 基于硬件指纹的确定性 UUID 生成
│   │   │   └── SessionCrypto.swift         # X25519 ECDH、ChaCha20-Poly1305、libsodium 封装
│   │   └── P2P/
│   │       ├── SignalingClient.swift       # HTTP/2 & HTTP/3 信令（伪装 OpenAI API SSE）
│   │       ├── DataChannelManager.swift    # libdatachannel Swift 桥接
│   │       ├── HolePuncher.swift           # 多端 STUN 探测、端口预测、生日攻击逻辑
│   │       ├── TURNClient.swift            # TURN Allocation / Relay  Fallback
│   │       └── DiscoveryService.swift      # 向服务器注册 UUID、查询对端网络坐标
│   └── project.yml / XcodeProj
├── Controller/                 # 控制端 (macOS / iOS / Web)
│   ├── macOS/                  # 优先实现 macOS 原生控制端
│   │   ├── Sources/
│   │   │   ├── VideoDecoder.swift
│   │   │   ├── InputCapture.swift          # 捕获本地鼠标/键盘
│   │   │   ├── RemoteView.swift            # Metal 渲染远程画面
│   │   │   ├── Crypto/
│   │   │   │   ├── KeyManager.swift        # 控制端 ed25519 私钥存储 (Secure Enclave)
│   │   │   │   └── SessionCrypto.swift     # 共享的 X25519 / libsodium 封装
│   │   │   ├── P2P/
│   │   │   │   ├── SignalingClient.swift   # HTTP/2 & HTTP/3 信令客户端
│   │   │   │   ├── DiscoveryService.swift  # 查询受控端 UUID / 公钥
│   │   │   │   ├── HolePuncher.swift       # 与控制端共享的打洞逻辑
│   │   │   │   └── TURNClient.swift        # TURN Relay 支持
│   │   │   └── ...
│   └── Web/                    # 可选：浏览器控制端 (WebRTC DataChannel)
├── Signaling/                  # 信令与发现服务 (Go)
│   ├── main.go                 # HTTP/2 & HTTP/3 (quic-go) 服务入口
│   ├── handler.go              # `/v1/chat/completions` SSE 伪装接口
│   ├── registry.go             # UUID ↔ 网络坐标 / ed25519 公钥 注册表
│   └── go.mod
├── Relay/                      # TURN 中继服务 (可选部署)
│   ├── turn_server.go          # 基于 pion/turn 的轻量转发，监听 443/UDP
│   └── docker-compose.yml
├── Shared/
│   └── Protocol/
│       ├── messagepack_schema.md       # 自定义帧格式与消息定义
│       └── nat_types.md                # NAT 类型枚举与 ICE Candidate 扩展定义
└── docs/
    ├── build.md                # 编译指南（如何桥接 libdatachannel）
    ├── permissions.md          # macOS TCC 权限详解
    ├── axui_limitations.md     # Accessibility 操作边界与 Fallback 策略
    ├── hole_punching.md        # 参考 Easytier 的打洞策略详解与端口预测算法
    └── bandwidth_tuning.md     # 硬件编解码参数、码率自适应与帧率控制策略
```

---

## 7. 风险与已知限制

1. **Accessibility API 局限**
   - 部分应用（如基于 CrossOver、某些游戏、旧版 Qt）的 UI 元素无法被 AXUI 识别，导致无法点击。
   - **Fallback**：对于这些情况，若用户接受短暂暴露，可切换至 `CGEventPost` 物理模拟（会移动光标），或在文档中声明为已知限制。

2. **ScreenCaptureKit 提示**
   - 每次启动捕获时，macOS 可能在菜单栏显示黄色“正在录制屏幕”指示器（macOS 13+）。
   - **缓解**：仅在收到远程连接请求且用户确认后开启捕获；UI 中可将其描述为 "AI 需要读取屏幕上下文以提供辅助"。

3. **辅助功能权限弹窗**
   - 首次使用需在系统设置中手动授权，弹窗显示 "ContextHelper 想控制这台电脑"。
   - **缓解**：仅在用户主动开启远程功能时才触发该请求；正常 AI 聊天无需此权限。

4. **P2P 连通率与 Fallback**
   - 对称 NAT / 企业防火墙可能导致 P2P 打洞失败。
   - **策略**：
     - 第一阶段：启用多端 STUN 探测 + 端口预测 + 同时发起连接（Easytier 策略），在绝大多数校园网 / 家庭 NAT 下可成功直连。
     - 第二阶段：若所有 P2P 候选均失败，**自动降级至 TURN 中继**，保证功能性，而非直接断开。
     - TURN 流量仍由 DTLS 加密，中继服务器无法窥探内容；且 TURN 可伪装成常规 443/UDP 流量。

5. **单用户会话**
   - macOS 非服务器系统，无法像 Windows 那样建立多用户并发会话。本地用户与远程操作共享同一 GUI Session。
   - **缓解**：设计上就是为“本地用户在前台使用，远程在后台辅助”而设计，非完全接管型工具。

---

## 8. 里程碑 (Milestones)

1. **M1 - 骨架**: 建立 Xcode 项目，完成 MenuBarExtra 伪装 UI，可调用 OpenAI API 正常聊天。
2. **M2 - 身份与发现体系**: 集成 `libsodium` (Swift-Sodium)，实现 ed25519 密钥对生成、Secure Enclave 存储、硬件指纹 UUID；部署支持 HTTP/2 & HTTP/3 的信令服务，完成设备注册与公钥查询。
3. **M3 - 信令与 P2P 握手**: 完成 libdatachannel 集成，实现多端 STUN 探测、端口预测、Simultaneous Open；服务器成功转发加密 SDP，建立直连 DataChannel。
4. **M4 - 画面与硬件编解码**: 集成 ScreenCaptureKit + VideoToolbox（H.264 / HEVC 硬件加速），实现动态码率/帧率/分辨率自适应，控制端实时解码显示。
5. **M5 - 幽灵输入**: 实现 AXUI 语义点击与键盘注入，验证物理光标不移动。
6. **M6 - 网络降级与打洞强化**: 集成 TURN Relay 作为 Fallback；参考 Easytier 实现端口预测、生日攻击与 IPv6 优先策略，提升校园网/对称 NAT 穿透率。
7. **M7 - 加固与伪装**: 加入 PSK 双因子认证、X25519 前向安全、MessagePack 协议定稿、icon/Bundle ID 伪装、CI 构建、TURN 服务器 Docker 化部署。

---

## 9. 开发环境限制与跨平台编译策略

> **现实约束**：由于内部网络监控，无法在 macOS 上直接搭建 OpenCode / Xcode 开发环境。所有代码必须在 Windows 端编写，通过 Git 同步后，在 macOS 端编译或完全依赖 CI 编译。

### 9.1 Windows 端开发方案

- **IDE**: VS Code + [Swift for VS Code](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) 扩展（基于 SourceKit-LSP）。
  - 支持语法高亮、代码补全、跳转到定义、Lint（SwiftFormat / swiftlint）。
  - **不支持**：Interface Builder / SwiftUI 实时预览、CoreSimulator、macOS SDK 头文件智能提示。
- **路径与换行符**
  - Git 配置 `core.autocrlf=false`，全局使用 LF 换行符，避免 Swift 编译器在 macOS 上解析出错。
  - 所有脚本（Build Phase、Run Script）使用 POSIX 路径（`/bin/sh`），避免 Windows 路径混用。
- **模块拆分与无头编译**
  - 将业务逻辑（P2P、编解码、协议解析）拆分为纯 Swift Package（`Package.swift`），这些模块可在 Windows 上通过 `swift build`（交叉语法检查）验证编译正确性，无需 Xcode。
  - 仅依赖 AppKit/SwiftUI 的 UI 层代码（`Agent/App/`、`Controller/macOS/`）在 Windows 上无法编译，需保持轻量，减少修改频率。
- **模拟测试**
  - P2P 协议层、MessagePack 编解码、加密逻辑可通过 Swift Package Manager 的 `XCTest` 在 Windows 上编写单元测试，提前发现语法与逻辑错误。
  - 对于 macOS 专属 API（`ScreenCaptureKit`、`VideoToolbox`、`AXUIElement`），在 Windows 端只能做接口mock / 伪代码编写，真正的集成测试必须在 macOS 环境进行。

### 9.2 macOS 端本地编译（最小化方案）

- 若用户可在 macOS 上安装 **Command Line Tools for Xcode**（约 1GB，不含 Xcode IDE），则可通过 Git 拉取仓库后直接：
  ```bash
  cd Agent && swift build
  cd ../Signaling && go build
  ```
- 如果需要 GUI 应用打包，仍需 Xcode 的 `xcodebuild` 或 `xcrun`，此时可以：
  1. 在 Windows 端写好代码。
  2. 通过 U 盘 / 加密压缩包 / Git 私有仓库传输到 macOS。
  3. 在 macOS 上执行 `xcodebuild -project Agent.xcodeproj -scheme ContextHelper` 编译。
- **注意**：此方案仍需要在 macOS 上安装基础开发工具，且无法完全避免网络监控（因为 `xcodebuild` 可能需要联网检查签名/证书）。

### 9.3 推荐方案：GitHub Actions CI 全自动编译

> **这是目前最干净、最彻底的解法**。用户在 Windows 端写代码并 push 到 GitHub，由 GitHub 的 macOS Runner 完成编译、签名、打包、发布，最终产物为一个 `.app` 或 `.dmg`，用户只需下载到 Mac 上双击运行。

#### CI 工作流设计 (`.github/workflows/build.yml`)

```yaml
name: Build & Release

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build-agent:
    runs-on: macos-latest          # GitHub 提供的 macOS 虚拟机
    steps:
      - uses: actions/checkout@v4

      # 1. 编译纯 Swift Package（业务逻辑层）
      - name: Build Swift Packages
        run: |
          cd Agent
          swift build -c release

      # 2. 编译 Xcode 项目（GUI 层）
      - name: Build Xcode Project
        env:
          DEVELOPER_DIR: /Applications/Xcode_15.2.app/Contents/Developer
        run: |
          xcodebuild -project Agent/ContextHelper.xcodeproj \
                     -scheme ContextHelper \
                     -configuration Release \
                     -derivedDataPath build \
                     CODE_SIGN_IDENTITY="-" \
                     CODE_SIGNING_REQUIRED=NO \
                     ARCHS="arm64 x86_64"  # Universal Binary

      # 3. 打包为 .app + .dmg
      - name: Package
        run: |
          mkdir -p dist
          cp -R build/Build/Products/Release/ContextHelper.app dist/
          hdiutil create -volname "ContextHelper" -srcfolder dist/ContextHelper.app -ov -format UDZO dist/ContextHelper.dmg

      # 4. 上传 Release
      - name: Upload to Release
        uses: softprops/action-gh-release@v1
        with:
          files: dist/ContextHelper.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### 代码签名与公证策略

| 场景 | 签名方式 | 效果 |
|------|----------|------|
| **无 Apple Developer 账号** | Ad-hoc 签名 (`codesign -s -`) | 可运行，但首次打开需用户在系统设置中手动允许；无法公证 |
| **个人 Apple Developer ($99/年)** | 开发者证书签名 + 公证 (Notarization) | 用户下载后双击直接打开，无 Gatekeeper 拦截，体验最佳 |
| **学校电脑无管理员权限安装证书** | Ad-hoc 签名即可 | 不依赖系统钥匙串安装根证书 |

- **CI 中的证书注入（如选择个人账号）**：
  - 将 `Certificates.p12` 与 `Provisioning Profile` 以 Base64 形式存入 GitHub Secrets (`MACOS_CERTIFICATE`, `MACOS_PP`)。
  - CI 运行时解码并导入到临时钥匙串，编译完成后立即删除，不在 runner 上留痕。
  - 参考脚本：
    ```bash
    echo "$MACOS_CERTIFICATE" | base64 --decode > certificate.p12
    security create-keychain -p "ci" build.keychain
    security import certificate.p12 -k build.keychain -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "ci" build.keychain
    ```

#### Go 信令服务器的 CI

```yaml
  build-signaling:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - run: cd Signaling && GOOS=linux GOARCH=amd64 go build -o dist/signaling-server
      - uses: softprops/action-gh-release@v1
        with:
          files: Signaling/dist/signaling-server
```

### 9.4 开发-编译-测试循环优化

- **快速验证**：Windows 端每次 commit 先触发 `swift build`（纯 Swift Package）和 `go build`（信令服务），确保语法正确。
- **定期集成**：每晚或每周末触发一次 GitHub Actions macOS 完整构建，产出 `.dmg`，用户下载到 Mac 上测试实际功能（屏幕录制、AXUI、P2P）。
- **Bug 修复循环**：
  1. Windows 端复现逻辑 / 修改代码 → Push 到 GitHub。
  2. GitHub Actions 自动编译 → Release 产出 `.dmg`。
  3. Mac 端下载测试 → 记录日志 / 录屏 → 反馈到 Windows 端继续修改。
- **日志回传**：Mac 端测试时，App 将日志写入 `~/Library/Application Support/ContextHelper/logs/`，测试结束后通过 iCloud Drive / 加密压缩包传回 Windows 端分析。

---

## 10. 命名建议 (供参考)

| 项目 | 建议值 |
|------|--------|
| 应用显示名 | `ContextHelper` / `MindMirror` |
| Bundle ID | `com.independent.contexthelper` |
| 菜单栏图标 | 灯泡 / 星星 / 对话气泡 (SF Symbols) |
| 进程名 | `ContextHelper` |
| 签名 Team | 个人 Apple Developer Account 即可 |

---

**结论**: 这是一个在 macOS 用户空间内，利用官方 API 实现的隐蔽后台控制方案。通过 Accessibility 语义层操作替代 HID 注入，彻底避免了物理光标位移；通过 AI 助手外壳与 P2P 直连设计，最大程度降低了被网络策略和本地审计发现的风险。
