# Discord Channel → Agent 路由

## 核心概念

透過 `bindings` 設定，讓不同 Discord channel 呼叫不同的 agent。

## 方式一：單 Bot + Peer Routing（推薦起步）

用一個 bot，按 channel ID 分流到不同 agent：

```json5
{
  bindings: [
    // #study channel → study agent
    { agentId: "study", match: { channel: "discord", peer: { kind: "channel", id: "STUDY_CHANNEL_ID" } } },
    // #finance channel → finance agent
    { agentId: "finance", match: { channel: "discord", peer: { kind: "channel", id: "FINANCE_CHANNEL_ID" } } },
    // 其餘 → home agent
    { agentId: "home", match: { channel: "discord", accountId: "*" } }
  ]
}
```

## 方式二：多 Bot（完全隔離）

每個 agent 一個 Discord bot token：

```json5
{
  channels: {
    discord: {
      accounts: {
        home: {
          token: "BOT_TOKEN_HOME",
          guilds: {
            "GUILD_ID": {
              channels: {
                "HOME_CHANNEL_ID": { allow: true, requireMention: false }
              }
            }
          }
        },
        study: {
          token: "BOT_TOKEN_STUDY",
          guilds: {
            "GUILD_ID": {
              channels: {
                "STUDY_CHANNEL_ID": { allow: true, requireMention: false }
              }
            }
          }
        }
      }
    }
  },
  bindings: [
    { agentId: "home", match: { channel: "discord", accountId: "home" } },
    { agentId: "study", match: { channel: "discord", accountId: "study" } }
  ]
}
```

## 路由匹配優先順序（first match wins）

1. `peer` match（精確 channel/DM ID）
2. `parentPeer` match（thread 繼承）
3. `guildId + roles`（Discord 角色路由）
4. `guildId`（Discord guild）
5. `accountId` 精確匹配
6. `accountId: "*"`（channel 全域 fallback）
7. Default agent

## Thread Binding（進階）

長時間工作可以綁定到 Discord thread 內：

```json5
{
  channels: {
    discord: {
      threadBindings: {
        enabled: true,
        idleHours: 24,
        maxAgeHours: 0
      }
    }
  }
}
```

Thread 指令：
- `/focus` — 綁定 thread 到 agent session
- `/unfocus` — 解除綁定
- `/agents` — 列出可用 agent

## Discord Bot 設定 Checklist

- [ ] 在 Discord Developer Portal 建立 bot
- [ ] 開啟 Message Content Intent（最常見的問題來源）
- [ ] 開啟 Server Members Intent
- [ ] 設定最小權限：View Channels、Send Messages、Read Message History
- [ ] 將 bot 加入 guild
- [ ] 在 openclaw.json 設定 token 和 channel allowlist
