# Kage 开发文档

## 项目概述

Kage (影) 是一个隐蔽的 macOS 远程桌面与自动化控制解决方案，伪装成一个本地 AI 助手。

## 已完成模块

### 1. Agent (macOS 被控端)

**目录结构:**
```
Agent/
├── Package.swift
├── Sources/
│   ├── App/           # SwiftUI 伪装 UI
│   ├── Core/          # 核心功能模块
│   ├── Crypto/        # 加密与身份管理
│   └── P2P/           # P2P 网络模块
└── Tests/
```

**已实现功能:**
- ✅ SwiftUI 伪装 UI (聊天窗口、菜单栏、设置页)
- ✅ ScreenCaptureKit 屏幕捕获
- ✅ VideoToolbox 硬件编码 (H.264/HEVC)
- ✅ AXUI 无光标输入控制
- ✅ 权限管理 (屏幕录制、辅助功能)
- ✅ ed25519 密钥管理
- ✅ UUID 设备标识生成
- ✅ X25519 会话加密
- ✅ P2P 信令客户端
- ✅ DataChannel 管理
- ✅ NAT 穿透 (HolePuncher)
- ✅ TURN 客户端
- ✅ 设备发现服务

### 2. Controller (控制端)

**目录结构:**
```
Controller/macOS/
├── Package.swift
├── Sources/
│   ├── KageControllerApp.swift
│   ├── ContentView.swift
│   ├── RemoteDesktopView.swift
│   ├── VideoDecoder.swift
│   └── InputCapture.swift
└── Tests/
```

**已实现功能:**
- ✅ macOS 控制应用程序
- ✅ Metal 远程桌面渲染
- ✅ VideoToolbox 硬件解码
- ✅ 鼠标和键盘输入捕获
- ✅ 连接管理界面
- ✅ 性能监控 (FPS、延迟、码率)

### 3. Signaling (信令服务器)

**目录结构:**
```
Signaling/
├── main.go
├── handler.go
├── registry.go
├── config.go
└── quic.go
```

**已实现功能:**
- ✅ HTTP/2 信令服务
- ✅ HTTP/3 (QUIC) 信令服务
- ✅ 伪装成 OpenAI API
- ✅ 设备注册与发现
- ✅ 信令消息转发
- ✅ 心跳机制

### 4. Relay (TURN 中继服务器)

**目录结构:**
```
Relay/
├── turn_server.go
├── go.mod
├── Dockerfile
└── docker-compose.yml
```

**已实现功能:**
- ✅ TURN 服务器实现
- ✅ UDP 中继功能
- ✅ 会话管理
- ✅ Docker 支持

### 5. Shared (共享协议)

**目录结构:**
```
Shared/Protocol/
├── messagepack_schema.md
└── nat_types.md
```

**已定义内容:**
- ✅ MessagePack 协议规范
- ✅ NAT 类型定义
- ✅ ICE 候选扩展

## 版本历史

- **v0.0.1**: 初始项目结构
- **v0.0.2**: 实现核心模块
- **v0.0.3**: 实现控制端
- **v0.0.4**: 实现 TURN 服务器
- **v0.0.5**: 添加测试文档

## 下一步开发计划

### M6 - 网络降级与打洞强化
- [ ] 集成 TURN Relay 作为 Fallback
- [ ] 实现端口预测算法
- [ ] 实现生日攻击策略
- [ ] IPv6 优先策略

### M7 - 加固与伪装
- [ ] PSK 双因子认证
- [ ] X25519 前向安全完善
- [ ] MessagePack 协议定稿
- [ ] Icon/Bundle ID 伪装
- [ ] CI 构建完善
- [ ] TURN 服务器 Docker 化部署

## 测试指南

请参考 [testing.md](testing.md) 进行测试。

## 构建说明

### Agent
```bash
cd Agent
swift build -c release
```

### Controller
```bash
cd Controller/macOS
swift build -c release
```

### Signaling
```bash
cd Signaling
go build -o signaling-server
```

### Relay
```bash
cd Relay
docker-compose up -d
```

## 注意事项

1. **macOS 权限**: 首次运行需要授予屏幕录制和辅助功能权限
2. **网络配置**: 确保防火墙允许相关端口通信
3. **密钥安全**: 私钥应安全存储，避免泄露
4. **版本管理**: 未完成前使用 v0.0.x 版本号

## 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 许可证

MIT License
