# LSerial

高吞吐跨平台通信调试工具，使用 Flutter 单代码库实现。当前 MVP 重点是稳定的数据通路：接收、缓存、批量刷新和虚拟化显示解耦。

## 平台能力

| 功能 | Windows | macOS | Linux | Web Chrome |
| --- | --- | --- | --- | --- |
| Serial | 支持，`flutter_libserialport` | 支持，`flutter_libserialport` | 支持，`flutter_libserialport` | Web Serial 接入点，需 HTTPS/localhost 和用户授权 |
| Bluetooth | 已隔离 adapter，MVP 禁用 | 已隔离 adapter，MVP 禁用 | 已隔离 adapter，MVP 禁用 | Web Bluetooth 能力探测，BLE GATT 待接入 |
| TCP Client | 支持，`dart:io` | 支持，`dart:io` | 支持，`dart:io` | 不支持，UI 禁用 |
| TCP Server | 支持，`dart:io` | 支持，`dart:io` | 支持，`dart:io` | 不支持，UI 禁用 |
| UDP | 支持，`dart:io` | 支持，`dart:io` | 支持，`dart:io` | 不支持，UI 禁用 |

Web 端是纯静态前端，无后端依赖。浏览器不暴露原生 TCP/UDP socket，所以 Web 端不会伪造 TCP/UDP 支持。

## 目录结构

```text
lib/
  main.dart
  app/                    # MaterialApp 和主界面 shell
  application/            # SessionController、ReceivePipeline
  core/                   # 字节环形缓存、HEX/ASCII、节流工具
  domain/                 # TransportType、ConnectionConfig、DataFrame、SendRequest
  features/
    connection/           # 连接方式和参数配置 UI
    console/              # 接收显示区、虚拟列表、过滤和工具栏
    send_panel/           # 发送区、定时发送、常用命令、历史
  platform/               # 桌面/Web 能力探测，条件导入隔离
  protocol/               # 帧格式化，ASCII/HEX 展示
  storage/                # LogBuffer 和日志导出
  transports/
    transport_registry.dart
    adapters/             # Serial/TCP/UDP/Bluetooth 平台适配
```

## 性能策略

- 原始字节进入 `ByteRingBuffer`，保留最近数据并统计淘汰字节。
- `ReceivePipeline` 按 33ms 时间片批量提交 `DataFrame`，不会逐条触发 UI rebuild。
- `LogBuffer` 限制最大显示帧数和最大缓存字节数，旧显示帧淘汰但接收链路不被 UI 阻塞。
- 暂停显示只冻结 UI snapshot，底层接收和缓存继续进行。
- 接收区使用 `ListView.builder` 和固定 `itemExtent`，避免无限 append 造成布局成本失控。
- ASCII/HEX 格式化只在显示层按可见列表需求执行，后续协议解析可迁移到 isolate。

## 本地运行

安装依赖并检查设备：

```powershell
flutter doctor -v
flutter pub get
flutter devices
```

Windows：

```powershell
flutter config --enable-windows-desktop
flutter run -d windows
```

macOS：

```bash
flutter config --enable-macos-desktop
flutter run -d macos
```

Linux：

```bash
flutter config --enable-linux-desktop
flutter run -d linux
```

Web Chrome：

```bash
flutter run -d chrome
```

## 构建

Windows Release：

```powershell
flutter build windows
```

产物：

```text
build/windows/x64/runner/Release/lserial.exe
```

Web 静态产物：

```bash
flutter build web --release
```

产物：

```text
build/web
```

如果 Windows 遇到 CMake 生成器缓存不一致：

```powershell
flutter clean
flutter pub get
flutter build windows
```

## 测试

```bash
flutter analyze
flutter test
flutter build web
flutter build windows
```

当前测试覆盖：

- `ByteRingBuffer` 环形缓存和淘汰统计
- `LogBuffer` 显示窗口淘汰
- `ReceivePipeline` 高频输入批量 flush
- 主界面 smoke test

## Cloudflare Pages

Cloudflare Pages 推荐配置：

```text
Build command: flutter build web --release
Build output directory: build/web
```

Web Serial/Web Bluetooth 只能在 Chrome、HTTPS 或 localhost、用户授权手势下使用。Cloudflare Pages 默认 HTTPS，满足浏览器安全上下文要求。

## 后续优先级

必做：

- 桌面 Bluetooth 明确 BLE/SPP 目标后接入稳定插件或原生桥。
- Web Bluetooth 完成 BLE GATT service/characteristic 选择、notify、write。
- 增加自动日志滚动落盘，保证超长运行时显示淘汰不影响完整日志。

应做：

- 多标签会话持久化。
- 连接配置 profile 保存/导入。
- 发送脚本导入格式定义。
- 更强搜索过滤和导出过滤。

可做：

- Modbus、AT、SCPI、自定义协议解析器。
- 接收解析迁移 isolate。
- 吞吐统计图和延迟统计。
