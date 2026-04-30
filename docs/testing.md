# Kage 测试指南

## 前置条件

1. macOS 13.0 (Ventura) 或更高版本
2. Xcode 15.0 或更高版本
3. Xcode Command Line Tools

## 测试步骤

### 1. 克隆仓库

```bash
git clone git@github.com:YuanZhe-99/Kage.git
cd Kage
```

### 2. 构建 Agent (被控端)

```bash
cd Agent
swift build -c release
```

构建完成后，可执行文件位于 `.build/release/ContextHelper`

### 3. 运行 Agent

```bash
.build/release/ContextHelper
```

首次运行时，系统会请求以下权限：
- 屏幕录制权限
- 辅助功能权限

请在系统设置中授权。

### 4. 构建 Controller (控制端)

```bash
cd Controller/macOS
swift build -c release
```

构建完成后，可执行文件位于 `.build/release/KageController`

### 5. 运行 Controller

```bash
.build/release/KageController
```

### 6. 测试信令服务器 (可选)

```bash
cd Signaling
go run main.go handler.go registry.go config.go quic.go
```

服务器将在端口 443 上启动（需要管理员权限）

### 7. 测试 TURN 服务器 (可选)

```bash
cd Relay
docker-compose up -d
```

## 测试功能

### 基本功能

1. **UI 伪装**: 验证 Agent 显示为正常的 AI 助手界面
2. **菜单栏**: 验证 Agent 在菜单栏显示图标
3. **聊天功能**: 验证 AI 聊天功能正常工作

### 远程控制功能

1. **屏幕捕获**: 验证 Agent 能够捕获屏幕
2. **视频编码**: 验证视频编码正常工作
3. **输入控制**: 验证远程输入控制功能

### 网络功能

1. **P2P 连接**: 验证点对点连接建立
2. **NAT 穿透**: 验证 NAT 穿透功能
3. **TURN 中继**: 验证 TURN 中继作为后备方案

## 故障排除

### 权限问题

如果遇到权限问题，请检查：
- 系统设置 > 隐私与安全性 > 屏幕录制
- 系统设置 > 隐私与安全性 > 辅助功能

### 构建问题

如果遇到构建问题，请确保：
- Xcode 版本 >= 15.0
- 已安装 Xcode Command Line Tools
- Swift 版本 >= 5.9

### 网络问题

如果遇到网络连接问题，请检查：
- 防火墙设置
- 网络连接状态
- 信令服务器是否正常运行

## 下一步

1. 测试完整的远程控制流程
2. 验证安全性和加密功能
3. 测试不同网络环境下的连接稳定性
4. 优化性能和用户体验

## 反馈问题

如果遇到问题，请在 GitHub 上提交 issue：
https://github.com/YuanZhe-99/Kage/issues
