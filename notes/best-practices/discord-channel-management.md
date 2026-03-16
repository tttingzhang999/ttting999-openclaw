# Discord Channel 管理能力

## 目前狀態（2026-03）

OpenClaw 對 Discord channel 的管理能力**有限**。

## 可以做的

- 發送 / 編輯 / 刪除 / 釘選訊息
- React（表情回應）
- 建立 Thread
- 處理 mention 和 DM
- 自動分段（超過 2000 字元自動切割）

## 有限支援

- `channel-create` / `channel-edit` 存在，但**不支援 permission_overwrites**
  - [Issue #26197](https://github.com/openclaw/openclaw/issues/26197)
- Channel permission set/remove 內部存在但未暴露給 message tool API

## 不支援

- 完整 guild 管理（建立/刪除 channel、角色管理等）
  - [Issue #458](https://github.com/openclaw/openclaw/issues/458) 仍 open

## 不支援

- Voice channel

## Workaround：透過 exec + Discord API

如果需要完整的 channel 管理，可以寫 skill 透過 `exec` tool 呼叫 Discord REST API：

```bash
# 建立 channel（需要 bot token 有 MANAGE_CHANNELS 權限）
curl -X POST "https://discord.com/api/v10/guilds/GUILD_ID/channels" \
  -H "Authorization: Bot BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "new-channel", "type": 0}'
```

或用 Python script 搭配 discord.py，放在 skill 目錄內由 exec 執行。

## Bot 權限建議

最小權限起步：
- View Channels
- Send Messages
- Read Message History

需要 channel 管理時才加：
- Manage Channels
- Manage Roles（如果需要 permission overwrites）

**避免使用 Administrator 權限**（除非 debug）。
