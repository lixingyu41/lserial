# LSerial MCP 使用说明

LSerial 桌面客户端内置 MCP（Model Context Protocol，模型上下文协议）服务，使 AI 客户端能够操作 LSerial 的连接页、串口、BLE、TCP、UDP、收发日志和统计。服务默认开启，监听：

```text
http://127.0.0.1:8765/mcp
```

开关位于连接面板右下角的“统计 > 设置 > MCP 服务”。Web 版只显示“仅桌面客户端可用”，不会启动服务。

## 安全边界

- 服务只绑定 `127.0.0.1`，局域网和公网主机不能连接。
- HTTP Host 仅允许 `localhost` 和 `127.0.0.1`，启用 MCP SDK 的 DNS 重绑定防护。
- MCP 调用与用户操作共享同一连接状态和发送队列；连接、配置、扫描等写操作按顺序执行。
- 只有 AI 通过 MCP 发出的 TX 数据使用来源 `AI[1]`；MCP 服务和控制操作日志均使用 `SYS`。

## 客户端配置

在支持 Streamable HTTP MCP 的 AI 客户端中添加以下服务器 URL：

```text
http://127.0.0.1:8765/mcp
```

使用 MCP Inspector 验证：

```powershell
npx @modelcontextprotocol/inspector --cli http://127.0.0.1:8765/mcp --transport streamable-http --method tools/list
```

客户端也可以读取 `lserial://guide` 和 `lserial://state` 资源，或使用 `lserial-upper-computer` 提示模板。

## 推荐操作顺序

1. 调用 `lserial_list_sessions`，保存返回的 `session_id`；省略该参数时操作当前连接页。
2. 串口先调用 `lserial_scan_serial_ports`，BLE 先调用 `lserial_scan_bluetooth`，再调用 `lserial_configure_connection`。
3. 调用 `lserial_connect`，确认返回的 `status` 为 `connected` 后发送；用 `lserial_read_log` 增量读取收发数据，用 `lserial_read_statistics` 读取统计。

修改连接参数或删除连接页前必须先断开。读取日志时把上次返回的 `next_sequence` 作为下一次的 `after_sequence`，避免重复读取。

## 工具

| 工具 | 用途 | 主要参数 |
| --- | --- | --- |
| `lserial_get_state` | 读取工作区、能力、配置和连接状态 | 无 |
| `lserial_list_sessions` | 列出连接页和 ID | 无 |
| `lserial_create_session` | 新建并激活连接页 | 无 |
| `lserial_delete_session` | 删除已断开的连接页 | `session_id` |
| `lserial_activate_session` | 切换 LSerial 当前连接页 | `session_id` |
| `lserial_scan_serial_ports` | 刷新系统串口 | `session_id` 可选 |
| `lserial_scan_bluetooth` | 扫描 BLE 设备 | `session_id`、`timeout_ms=5000` |
| `lserial_configure_connection` | 选择连接方式并更新参数 | 见下表 |
| `lserial_connect` | 打开连接 | `session_id` 可选 |
| `lserial_disconnect` | 关闭连接 | `session_id` 可选 |
| `lserial_send` | 发送字节 | `data`、`format`、`line_ending` |
| `lserial_read_log` | 增量读取收发和系统日志 | `after_sequence`、`direction`、`max_frames`、`max_bytes` |
| `lserial_read_statistics` | 读取帧数、字节数、速率、时长和缓存 | `session_id` 可选 |
| `lserial_read_raw_receive` | 不等待分包，读取最近收到的原始字节 | `session_id`、`max_bytes` |
| `lserial_clear_log` | 清空一个连接页的日志和统计 | `session_id` 可选 |
| `lserial_set_console_options` | 设置显示格式、发送格式、换行、滚动和暂停 | 对应选项字段 |
| `lserial_list_quick_commands` | 读取快捷指令 | `session_id` 可选 |
| `lserial_create_quick_command` | 新建快捷指令 | `name`、`content`、`format` |
| `lserial_update_quick_command` | 更新快捷指令 | `command_id` 及指令字段 |
| `lserial_delete_quick_command` | 删除快捷指令 | `command_id` |
| `lserial_execute_quick_command` | 以 `AI[1]` 执行快捷指令 | `command_id` |
| `lserial_start_auto_send` | 启动 `AI[1]` 定时发送 | `data`、`format`、`line_ending`、`interval_ms` |
| `lserial_stop_auto_send` | 停止定时发送 | `session_id` 可选 |

`session_id` 可省略或传 `active` 表示当前连接页。创建和删除后应重新调用 `lserial_list_sessions`。

## 连接参数

`lserial_configure_connection` 只修改传入字段，未传字段保持原值。

| 类型 | `type` | 参数 |
| --- | --- | --- |
| 串口 | `serial` | `port_name`、`baud_rate`、`data_bits`、`stop_bits`、`parity`、`packet_interval_ms`、`packet_delimiter` |
| 串口转发 | `serial` | 上述参数，以及 `forwarding_enabled`、`forward_port_name`、`forward_baud_rate` |
| BLE | `bluetooth` | `device_id`、`device_name`、`service_uuid`、`write_characteristic_uuid`、`notify_characteristic_uuid`、`write_without_response` |
| TCP 客户端 | `tcp_client` | `host`、`port` |
| TCP 服务端 | `tcp_server` | `bind_address`、`port` |
| UDP | `udp` | `bind_address`、`local_port`、`remote_host`、`remote_port` |

串口约束：`data_bits` 为 `5/6/7/8`，`stop_bits` 为 `1/2`，`parity` 为 `none/odd/even`。网络端口范围为 `1..65535`。

## 发送与日志

`lserial_send.format` 支持 `ascii`、`hex`、`base64`；`line_ending` 支持 `none`、`cr`、`lf`、`crlf`。HEX 示例：

```json
{
  "session_id": "session_1",
  "data": "AA 55 01 00 FF",
  "format": "hex",
  "line_ending": "none"
}
```

日志每帧返回 `sequence`、ISO 8601 时间、`direction`、`source`、字节长度，以及 `hex`、UTF-8 `text`、`base64` 三种表示。单次最多返回 500 帧和 262144 字节；`direction` 支持 `all/rx/tx/system`。

## 给 AI 的约束

- 未经用户明确要求，不要自动连接扫描结果中的设备，也不要向设备发送探测命令。
- 配置前读取当前状态；串口和 BLE 选择必须来自当前扫描结果或用户明确给出的标识。
- 每次发送后读取 TX 日志确认写入，再按协议需要轮询 RX；轮询必须推进 `after_sequence`。
- 连接失败时返回 `status_message` 给用户，不要高频重试。每次失败最多重试 1 次，两次尝试间隔至少 1000 ms。
- 完成一次临时任务后关闭由 AI 打开的连接；不要关闭用户原本已经连接的会话。
