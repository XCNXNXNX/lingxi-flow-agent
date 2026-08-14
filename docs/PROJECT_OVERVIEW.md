# 灵犀流序 (Lingxi Flow) — 完整项目文档

> **面向用户/评委的功能说明请见**：`docs/软件说明.md`
> **上架审核规范对照**：`docs/上架审核规范.md` ｜ **踩坑经验手册**：`docs/开发经验记录.md` ｜ **上架操作指南**：`docs/上架指南.md`

> **平台**：HarmonyOS NEXT (API 14 / SDK 6.1.1)
> **语言**：ArkTS (严格模式，禁止 any/unknown/Record<>)
> **包名**：`com.lingxiflow.app`
> **文件数**：30 个 `.ets` 源文件（已精简），约 7500 行
> **阶段**：v1.1 — 跨设备协同上线：设备发现 / 任务进度同步 / 提醒分发（手机→手表）

---

## 零、给其他 AI 模型的开发提示词

如果你是一个要继续开发灵犀流序的 AI 模型，请按以下步骤开始工作：

```
你正在开发灵犀流序(Lingxi Flow)，一个 HarmonyOS NEXT 上的 AI Agent 应用。
纯 ArkTS 实现，基于 ReAct 推理循环。

项目在 C:\Huawei\Lingxi_app。完整文档是 docs/PROJECT_OVERVIEW.md，
请先完整阅读本文档。

参考架构源码：
  - C:\Huawei\nanoclaw-on-openharmony-main（NanoClaw 鸿蒙移植版，含完整 ReAct 模式）
  - https://github.com/anomalyco/openclaw（原始 OpenClaw Node.js 实现，40 万行)
你可以随时翻阅这两个参考仓库的任意源码文件来理解模式。

ArkTS 铁律（违反即编译失败）：
  1. 禁止使用 any、unknown、Record<> 类型
  2. 禁止匿名对象字面量（用 JSON.parse('...') as Type 或显式类型标注）
  3. new 关键字不能用于 interface（interface 必须用字面量创建）
  4. 资源引用必须用 $r() 而非字符串路径
  5. import/export 只能出现在文件顶层，不能在函数/块内部
  6. 类成员必须在声明或构造函数中初始化

开始开发前必须先读完 engine/AgentCore.ets 和 model/Types.ets。
修改代码时请保持现有代码风格和 ArkTS 规范。
```

---

## 一、项目概述

灵犀流序是一款让用户用自然语言描述需求、由大语言模型自主规划并执行的 AI Agent 移动应用。

### 核心概念

```
用户输入 "提醒我下午3点开会，查一下杭州天气"
  ↓
AgentCore (ReAct循环):
  Thought → 我需要创建提醒 + 查询天气
  Action  → tool: create_reminder("下午3点开会")
  Action  → tool: get_weather("杭州")
  Observation → 提醒已创建 + 天气多云25°C
  Answer  → "已为你创建下午3点的提醒，杭州目前多云25°C..."
  ↓
UI 实时展示: 工具调用步骤 + AI 文本回复
```

### 设计哲学

| 原则 | 说明 |
|------|------|
| **ReAct 循环** | Thought → Action → Observation → ... → Answer |
| **工具即插件** | 所有系统能力统一注册为 Tool，LLM 通过 Function Calling 调用 |
| **记忆持久化** | 对话历史、消息存入 SQLite，支持多对话和断点续传 |
| **UI 驱动** | Agent 循环由用户输入触发，事件（tool_use / text / done）实时推送 UI |
| **OpenAI 兼容** | API 格式兼容 OpenAI/DeepSeek/GLM/Ollama 等所有兼容提供商 |

### 精简后的项目统计

- **总 `.ets` 源文件**：30 个，约 7500 行
- **核心引擎**：5 个文件（AgentCore, ToolRegistry, DatabaseService, RagService, TaskScheduler）
- **工具系统**：6 个文件（FileTools 8个 + ReminderTools 3个 + CalendarTools 3个 + WeatherTools 1个 + WebTools 2个 + MemoryTools 3个 = 20 工具）+ MCP 远程工具（`mcp_` 前缀）
- **页面**：7 个（Index 首页, ChatPage 对话, ResultPage 任务, SettingsPage 设置, FileBrowserPage 文件, KnowledgePage 知识库, DevicePage 跨设备）
- **UI 组件**：1 个（MarkdownText，AI 回复的轻量 Markdown 渲染）
- **支撑服务**：3 个（ApiClient, ConfigService, VoiceService）
- **工具类**：3 个（Logger, TextFormatter, ThemeService）
- **入口**：3 个（EntryAbility, EntryBackupAbility, InsightIntentExecutorImpl 小艺意图执行器）
- **类型**：1 个（Types.ets，所有 interface/class/enum 集中定义）

---

## 二、目录结构

```
entry/src/main/ets/
│
├── engine/                      # ★ 核心引擎层
│   ├── AgentCore.ets            # ReAct 推理循环 + 工具调用编排 + RAG 上下文注入
│   ├── ToolRegistry.ets         # 工具注册与调度
│   ├── DatabaseService.ets      # SQLite 持久化（关系型数据库）
│   ├── RagService.ets           # ★ RAG 知识库（BGE-M3 向量检索 / 关键词兑底）
│   └── TaskScheduler.ets        # 定时任务轮询（60s 间隔）
│
├── services/                    # 支撑服务
│   ├── ApiClient.ets            # HTTP LLM 客户端（OpenAI 兼容 API，含 SSE 流式）
│   ├── ConfigService.ets       # API 配置持久化（preferences + KV）
│   ├── VoiceService.ets        # 语音服务（SpeechKit ASR 听写 + TTS 播报）
│   └── McpClient.ets           # ★ MCP 客户端（Streamable HTTP，远程工具接入）
│
├── model/                       # 数据模型
│   └── Types.ets                # ★ 所有类型定义（interface/class/enum/type alias）
│
├── tools/                       # AI 可调用工具（按领域拆分）
│   ├── FileTools.ets            # 文件操作（8 个工具）
│   ├── ReminderTools.ets        # 提醒管理（3 个工具 + 系统通知）
│   ├── CalendarTools.ets        # 时间日期（3 个工具）
│   ├── WeatherTools.ets         # 天气查询（1 个工具，调用 wttr.in）
│   ├── WebTools.ets             # 网页搜索（Bing 优先 + DDG 兜底）+ 网页抓取（2 个工具）
│   └── MemoryTools.ets          # 长期记忆笔记（Markdown 文件，3 个工具）
│
├── components/                  # UI 组件
│   └── MarkdownText.ets         # 轻量 Markdown 渲染（#标题 / -列表 / **加粗** / `行内代码`）
│
├── pages/                       # 页面（@Entry）
│   ├── Index.ets                # ★ 主页 — 雪花粒子特效 + 底部四 Tab 导航
│   ├── ChatPage.ets             # ★ 对话界面 — AI 对话、API 配置、对话管理
│   ├── ResultPage.ets           # ★ 任务系统 — 输入目标 → AI 自主执行 → 步进展板
│   ├── SettingsPage.ets         # 设置 — 主题切换(龙虾/灵犀)、记忆管理、技能列表
│   └── FileBrowserPage.ets      # 文件管理器 — 沙盒目录浏览、创建/复制/重命名/删除
│
├── utils/                       # 工具类
│   ├── Logger.ets               # 日志封装（hilog）
│   ├── TextFormatter.ets        # ID 生成 + 字符串处理
│   └── ThemeService.ets         # 主题管理（AppStorage + preferences 持久化）
│
├── entryability/
│   ├── EntryAbility.ets         # ★ 应用入口 — 初始化所有服务
│   └── InsightIntentExecutorImpl.ets # 小艺意图执行器（JumpFunctionPage → 预填对话）
│
└── entrybackupability/
    └── EntryBackupAbility.ets   # 系统备份能力
```

---

## 三、架构详解

### 3.1 整体架构图

```
┌────────────────────────────────────────────────────────────┐
│                        ArkUI 前端                           │
│  ┌─────────┐  ┌────────────┐  ┌───────────┐  ┌─────────┐ │
│  │ Index   │  │ ChatPage   │  │ResultPage │  │Settings │ │
│  │ 主页+Tab│  │ 对话+API   │  │AI 任务    │  │主题+记忆│ │
│  └────┬────┘  └─────┬──────┘  └─────┬─────┘  └────┬────┘ │
│       │              │               │              │       │
│       │        ┌─────▼───────────────▼──────┐       │       │
│       │        │        AgentCore.ets       │       │       │
│       │        │        ReAct 推理循环       │       │       │
│       │        │                             │       │       │
│       │        │  用户输入 → ApiClient → LLM  │       │       │
│       │        │       ↓                     │       │       │
│       │        │  finish_reason?             │       │       │
│       │        │  ├─ "tool_calls" → 工具执行  │       │       │
│       │        │  └─ "stop" → 文本回复       │       │       │
│       │        └─────────┬───────────────────┘       │       │
│       │                  │                           │       │
│       │    ┌─────────────┼──────────────┐            │       │
│       │    │             │              │            │       │
│       │  ┌─▼───────┐ ┌──▼─────┐  ┌─────▼──────┐    │       │
│       │  │Database │ │ Tool   │  │  Task      │    │       │
│       │  │Service  │ │Registry│  │ Scheduler  │    │       │
│       │  │ SQLite  │ │ 25工具 │  │  60s 轮询   │    │       │
│       │  └─────────┘ └──┬─────┘  └────────────┘    │       │
│       │                 │                           │       │
│       │     ┌───────────┼───────────┐               │       │
│       │     │           │           │               │       │
│       │  FileTools  Reminder  Calendar/Weather      │       │
│       │  (8工具)   Tools(3)   Tools(3+1)            │       │
└───────┴──────────────────────────────────────────────┴───────┘
```

### 3.2 应用启动流程

```
EntryAbility.onCreate()
  ├─ configService.init(context)     // 加载 preferences
  ├─ dbService.init(context)          // 创建 SQLite 表
  ├─ ThemeService.init()              // 恢复主题设置
  ├─ agentCore.init(filesDir)         // 注册所有 25 个工具
  └─ taskScheduler.start()            // 启动定时任务轮询

EntryAbility.onWindowStageCreate()
  └─ loadContent('pages/Index')       // 加载首页
```

### 3.3 ReAct 推理循环（AgentCore.ets）

```
while (iterations < 15):
    1. POST { messages: [system + history], tools: [15种工具定义] } → LLM API
    2. 检查 response.choices[0].finishReason:
       ├─ "tool_calls":
       │    对于每个 tool_call:
       │      ├─ 加入 history（assistant 角色 + tool_calls）
       │      ├─ ToolRegistry.executeTool(name, args)
       │      ├─ 发送 tool_use 事件 → UI 更新
       │      ├─ 结果加入 history（tool 角色）
       │    继续循环（让 LLM 看到工具结果后继续推理）
       └─ "stop":
            发送 text 事件 → UI 显示最终回复
            消息存入 SQLite
            发送 done 事件 → UI 结束加载
            返回
```

关键常量和限制：
- `MAX_ITERATIONS = 15`（防止无限循环调用工具）
- `CONTEXT_WINDOW = 30`（每次加载最近 30 条历史消息）
- `SYSTEM_PROMPT` 定义了 Agent 的角色和可用工具说明

### 3.4 工具注册机制

工具注册遵循标准模式（以 `mkdir` 为例）：

```typescript
// 1. 定义 JSON Schema 入参（必须用 JSON.parse 避免匿名对象面量错误）
const SCHEMA: Record<string, Object> = JSON.parse(
  '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
) as Record<string, Object>

// 2. 注册到 ToolRegistry
registry.registerTool(
  'mkdir',                          // 工具名
  'Create a new directory',         // 描述（LLM 依据此判断何时调用）
  SCHEMA,                            // JSON Schema 入参
  async (input: Record<string, Object>) => {
    const path = input['path'] as string
    await fileIo.mkdir(resolvePath(path), true)
    return '已创建文件夹: ' + path
  }
)
```

### 3.5 全部 25 个 AI 工具

| 工具名 | 功能 | 来源文件 |
|--------|------|----------|
| `mkdir` | 创建目录 | FileTools.ets |
| `write_file` | 写入文件内容（自动创建父目录） | FileTools.ets |
| `read_file` | 读取文件内容 | FileTools.ets |
| `list_files` | 列出目录内容（最多 30 项） | FileTools.ets |
| `delete_file` | 删除文件 | FileTools.ets |
| `search_files` | 按关键词搜索文件名 | FileTools.ets |
| `copy_file` | 复制文件到剪贴板 | FileTools.ets |
| `paste_file` | 粘贴剪贴板文件到新位置 | FileTools.ets |
| `create_reminder` | 创建定时提醒（ReminderAgentKit 倒计时，到点触发系统通知） | ReminderTools.ets |
| `list_reminders` | 列出所有提醒 | ReminderTools.ets |
| `cancel_reminder` | 取消指定提醒 | ReminderTools.ets |
| `get_current_time` | 获取当前时间（时:分:秒） | CalendarTools.ets |
| `get_current_date` | 获取当前日期 + 星期 | CalendarTools.ets |
| `get_weekday` | 获取今天星期几 | CalendarTools.ets |
| `calendar_create` | 创建系统日历日程（提前 10 分钟提醒） | CalendarTools.ets |
| `calendar_query` | 查询未来 N 天日程 | CalendarTools.ets |
| `task_create` | 创建周期/一次性后台 AI 任务 | TaskTools.ets |
| `task_list` | 列出定时任务 | TaskTools.ets |
| `task_cancel` | 取消定时任务 | TaskTools.ets |
| `get_weather` | 查询城市天气（wttr.in API） | WeatherTools.ets |
| `web_search` | 网页搜索（Bing CN 优先，DuckDuckGo 兜底） | WebTools.ets |
| `web_fetch` | 抓取网页正文（去 HTML 标签，限 5 万字符） | WebTools.ets |
| `memory_write` | 写入长期记忆笔记（Markdown 文件） | MemoryTools.ets |
| `memory_read` | 读取记忆笔记 | MemoryTools.ets |
| `memory_list` | 列出所有记忆笔记 | MemoryTools.ets |

### 3.6 SQLite 数据库表结构

```sql
-- 对话表
chats (id TEXT PK, name TEXT, last_message_time TEXT, last_message_preview TEXT)

-- 消息表
messages (id TEXT PK, chat_id TEXT FK, sender TEXT, sender_name TEXT,
  content TEXT, timestamp TEXT, is_from_me INTEGER, tool_calls TEXT)

-- 定时任务表
scheduled_tasks (id TEXT PK, chat_id TEXT, prompt TEXT, schedule_type TEXT,
  schedule_value TEXT, next_run TEXT, last_run TEXT, last_result TEXT,
  status TEXT, created_at TEXT)

-- 任务运行日志
task_run_logs (id INTEGER PK AUTO, task_id TEXT, run_at TEXT,
  duration_ms INTEGER, status TEXT, result TEXT, error TEXT)

-- 键值存储
kv_store (key TEXT PK, value TEXT)
```

---

## 四、页面功能说明

### 4.1 Index.ets — 主页

- 应用图标呼吸缩放动画（3 秒循环）
- 打字机效果标题 "Lingxi Flow"（逐字显示）
- **20 个半透明小圆点雪花粒子**：各自独立的摆动速度/幅度，自然飘落动画，使用主题色 + 动态透明度（0.04~0.28 呼吸变化）
- 底部四 Tab 导航栏（按压缩放效果）：

| Tab | 标签 | 路由 |
|-----|------|------|
| 0 | 对话 | `pages/ChatPage` |
| 1 | 任务 | `pages/ResultPage` |
| 2 | 设置 | `pages/SettingsPage` |
| 3 | 文件 | `pages/FileBrowserPage` |

### 4.2 ChatPage.ets — 对话界面（核心交互）

- 消息气泡列表：用户靠右蓝色，AI 靠左灰色，支持 `List + scroller` 自动滚底
- **工具调用可视化**：每条消息下方显示使用的工具名标签（成功 `◎` / 失败 `✗`）
- **工具执行状态条**：底部实时显示 "正在调用: xxx"
- **Markdown 渲染**：AI 回复经 MarkdownText 组件渲染（标题 / 列表 / 加粗 / 行内代码）
- **SSE 真流式**：AI 回复边生成边显示（ApiClient 流式解析 + AgentStreamEvent 实时注入气泡）
- **语音输入**：输入框左侧 🎤 按钮，SpeechKit ASR 将语音转文字填入输入框（需要麦克风权限）
- **TTS 播报**：每条 AI 消息右下 🔊 按钮可朗读回复，再点停止
- **打字机效果**：非流式场景（离线兜底 / 错误提示）仍用逐字显示
- **API 配置面板**：设置 URL / Key / 模型 / 获取模型列表
- **对话管理**：新建、重命名、删除对话，对话列表侧滑面板
- **离线模式**：未配置 API 时使用 `getFallbackReply()` 关键词兜底
- **消息对删除**：用户消息可展开"删除本轮"按钮
- 发送按钮按压缩放动效

### 4.3 ResultPage.ets — AI 任务系统

新版任务页面已完全接入 AI：

- **任务输入栏**：输入自然语言描述，"→" 按钮发送
- **AI 自主执行**：调用 `agentCore.runAgent()` → AI 自行选择工具并执行
- **实时步进展板**：每个工具调用显示为一步，带状态图标、彩色圆形标记、时间线连接线
- **进度条**：按已执行步骤数动态增长的顶部进度条
- **重新执行 / 新任务**：完成后可一键重跑同一目标，或清空开始新任务
- **AI 响应卡片**：玻璃拟态卡片展示 AI 思考后的文本回复
- **执行时长统计**：任务耗时自动计时
- **完成弹窗**：绿色对勾圆形图标 + 阴影动画 + 任务摘要
- 未配置 API 时显示黄色提示条
- 提示词可点击直接填入执行

### 4.4 SettingsPage.ets — 设置

- **主题切换**：龙虾风格（深色/珊瑚色）↔ 灵犀风格（浅色/紫罗兰色）
  主题切换带边框高亮动画，持久化到 preferences
- **记忆管理**：键值对收藏（`memory_keys` + `mem_<key>` 存入 SQLite）
- **技能列表**：展开查看各技能的工具数量和状态

### 4.5 FileBrowserPage.ets — 文件管理器

- 沙盒目录 `/data/storage/el2/base/files` 浏览
- 文件/文件夹列表（图标 + 大小 + 修改时间）
- **新建对话框**（Stack 叠加层）：选择文件夹/文件 + 输入名称 + 创建
- **操作菜单**：复制 / 重命名 / 编辑 / 删除
- 粘贴剪贴板文件
- **内置文本编辑器**：点击文本文件直接编辑并保存（与 AI 共享沙盒路径）
- `onPageShow` 自动刷新目录
- 支持上级目录导航

---

## 五、关键实现细节

### 5.1 OpenAI 兼容 API 格式

`ApiClient.ets` 发送如下格式的 POST 请求：

```json
{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "你是灵犀..."},
    {"role": "user", "content": "用户输入"},
    {"role": "assistant", "content": "...", "tool_calls": [...]},
    {"role": "tool", "tool_call_id": "...", "content": "工具结果"}
  ],
  "tools": [{"type": "function", "function": {"name": "mkdir", "description": "...", "parameters": {...}}}],
  "max_tokens": 8192,
  "temperature": 0.7
}
```

### 5.2 ArkTS 兼容性处理

| 问题 | 解决方案 |
|------|----------|
| 匿名对象字面量报错 | 用 `JSON.parse('...') as Type` 定义 Schema 常量 |
| `Record<string, Object>` 访问 `input['key']` | 允许 `Record<string, Object>` 作为动态键类型 |
| `new` 不能用于 interface | 所有动态创建的类型用 `class` 而非 `interface` |
| 资源路径 | 始终使用 `$r('app.media.xxx')` 和 `$r('app.float.xxx')` |
| 字符串换行 | 用 `\n` 而非模板字符串跨行 |

### 5.3 文件操作安全

所有文件路径都经 `resolvePath()` 处理：
```typescript
function resolvePath(path: string): string {
  const normalized = path.replace(/\.\.\//g, '').replace(/\.\./g, '')
  return gBaseDir + '/' + normalized
}
```
确保：去除 `../` 防止路径穿越、统一加 `filesDir` 前缀、所有操作在沙盒内。

### 5.4 Markdown 渲染与打字机

- `MarkdownText` 组件解析 `# / ## / ###` 标题、`- / *` 列表项，并剥离 `**加粗**`、`*斜体*`、`` `行内代码` `` 标记（ArkTS 下无第三方 Markdown 库，采用轻量自绘）
- 打字机效果：`setInterval` 逐字追加到 "思考中..." 占位气泡，`isThinking` 状态实时驱动 UI，完成后替换为正式消息并写入 SQLite
- 删除本轮：用户消息生成 `pairId`，AI 回复继承同一 pairId，可成对删除（含数据库记录）

### 5.5 SSE 流式回复（v0.6）

- `ApiClient.sendMessageStream()`：POST `stream:true`，通过 `httpRequest.on('dataReceive')` 接收分片，`util.TextDecoder.decodeWithStream` 处理跨字节边界的中文，按 `\n` 切分 SSE 帧，`data: [DONE]` 或 `dataEnd` 事件终结
- 工具调用同样流式：`delta.tool_calls` 按 index 累积 `id/name/arguments` 分片，`finish_reason: "tool_calls"` 时组装完整 ToolCall 列表
- 容错（v0.6.1）：90 秒无数据看门狗自动失败；支持非标准服务商返回整段 `message` 而非 `delta`；AgentCore 在流式失败或返回空时自动回退非流式请求；ChatPage 在 done 事件强制复位 UI，任何异常都不会卡在"思考中"
- `AgentCore.runAgentStream()`：ReAct 循环内逐轮流式请求，文本增量通过 `AgentStreamEvent {type:'stream'}` 实时推送 UI，工具执行结果回传后继续下一轮
- 兼容性：OpenAI 兼容协议（DeepSeek / GLM / Ollama 等），非流式 `sendMessage()` 保留给 ResultPage / TaskScheduler 使用

### 5.6 语音服务（v0.6）

- `VoiceService.ets` 封装 `@kit.CoreSpeechKit`：
  - ASR：`speechRecognizer.createEngine({language:'zh-CN', online:1})` → `@kit.AudioKit` audioCapturer 采集 16kHz 单声道 PCM → `writeAudio(sessionId, Uint8Array)` → `onResult` 实时回填输入框；`finish()` 结束会话
  - TTS：`textToSpeech.createEngine` → `speak(text, {requestId, extraParams})`，`onComplete/onStop/onError` 回调复位状态
- 需要 `ohos.permission.MICROPHONE`（已声明，运行时弹窗申请）；在线识别/合成依赖网络
- 语音能力需真机验证（模拟器不支持 SpeechKit 引擎）

### 5.7 RAG 知识库（v0.7）

- `engine/RagService.ets`：知识来源为沙盒内 `memory/*.md`（AI 记忆笔记）、`knowledge/*.md|txt`（用户文档）、根目录 `*.md|txt`；按段落切块（400 字符/块，60 字符重叠）
- 向量模式：SiliconFlow `BAAI/bge-m3` 嵌入（OpenAI 兼容 `/v1/embeddings`，国内可达），余弦相似度取 top-3，向量以 Float32 二进制存 SQLite `lingxi_rag.db`
- 关键词兑底：未配置嵌入 Key 时自动切换为字符二元组重叠评分（中文友好），保证基础检索可用
- 增量重建：文件列表 + 大小 + mtime 组成内容签名，变化才重建；单飞防重入；MemoryTools 写入后 `markDirty()`
- 注入方式：每次对话前检索 top-3 块拼入 system prompt（`【知识库参考】...`），检索失败绝不影响对话
- 配置：对话页 API 面板「嵌入 Key（可选）」字段；嵌入 URL 可在 ConfigService 中改（默认 SiliconFlow）

### 5.8 MCP 远程工具（v0.8）

- `services/McpClient.ets`：Model Context Protocol 客户端，Streamable HTTP 传输，JSON-RPC 2.0
- 生命周期：`initialize`（携带 protocolVersion 2025-03-26 + clientInfo）→ `notifications/initialized` → `tools/list` → `tools/call`
- 兼容 SSE 包裹响应（`event:`/`data:` 行解析）与纯 JSON；`Mcp-Session-Id` 响应头提取并回传；会话过期自动重连重试一次
- 远程工具以 `mcp_` 前缀注册进 ToolRegistry（防与本地 20 工具冲突），executor 内部按原名调用 `tools/call`，content[].text 拼接返回
- 配置：对话页 API 面板「MCP 服务器（可选）」→ 保存后重启生效；未配置/连接失败时静默跳过，本地功能不受影响
- 联调：`C:\Huawei\mcp_test_server.js` 零依赖 mock 服务器（mcp_get_server_time / mcp_add_numbers / mcp_random_quote），协议链路已验证

### 5.9 系统日历（v0.9）

- `calendar_create`：写入系统日历（`@kit.CalendarKit`），支持绝对时间（`start_time` 毫秒时间戳）与相对时间（`minutes_from_now`），自动设置提前 10 分钟提醒，返回事件 ID
- `calendar_query`：`EventFilter.filterByTime` 查询未来 N 天（默认 7 天）日程
- `READ_CALENDAR` / `WRITE_CALENDAR` 为 user_grant 权限，工具执行时弹窗申请，拒绝则返回友好提示
- SYSTEM_PROMPT 已区分两个场景："X分钟后提醒" → create_reminder（倒计时通知）；"明天下午3点开会" → calendar_create（系统日程）
- 真机验证要点：首次调用会弹权限窗；模拟器无系统日历数据

### 5.10 小艺意图（v1.0）

- `resources/base/profile/insight_intent.json`：注册预置垂域意图 `JumpFunctionPage`（ToolsDomain，参数 `pageId`），绑定 EntryAbility（foreground 模式）——小艺说"打开XX"可唤起灵犀
- `entryability/InsightIntentExecutorImpl.ets`：继承 `InsightIntentExecutor`，`onExecuteInUIAbilityForegroundMode` 把意图参数翻译为预设提示词写入 `AppStorage.intentPresetText`
- ChatPage.aboutToAppear 消费预设 → 自动填入输入框并发送（演示链路：小艺 → 灵犀自动执行）
- 注意：意图名只能用 SDK 预置垂域（`ets/build-tools/ets-loader/insight_intents/schema/` 共 101 个），不允许自定义；小艺分发需真机 + 系统配置验证

### 5.11 断点续传（v1.0）

- `workflow_runs` 表（DatabaseService）：记录 goal / status / steps_json / result / chatId
- ResultPage 每步工具调用与文本回复都落库（running / done / error）；再次进入任务页显示"上次任务"卡片
- 「继续上次任务」复用原 `task_` chatId → AgentCore 自动加载完整历史上下文续跑（真正的断点续传，而非无状态重跑）

### 5.12 提醒持久化（v1.0）

- 提醒记录存入 SQLite kv（`lingxi_reminders`），重启后 `list_reminders` / `cancel_reminder` 仍可用
- `list_reminders` 合并 `reminderAgentManager.getValidReminders()`（系统层生效的提醒，杀进程后依然可查）
- 应用内兑底定时器触发后标记 fired 并持久化

### 5.13 知识库管理页（v1.0）

- `pages/KnowledgePage.ets`（设置 → 知识库管理）：显示索引模式（向量/关键词）、chunk 数、源文件列表（记忆/知识库/根目录）、重建索引、删除文件
- RagService 新增 `getChunkCount()` / `getSourceFiles()` / `forceRebuild()` / `getFilesDir()`

### 5.14 跨设备协同（v1.1，任务 5）

- `services/DistributedService.ets`：
  - 设备发现：`@kit.DistributedServiceKit` distributedDeviceManager `getAvailableDeviceList()` + `deviceStateChange` 监听
  - 状态同步：`@ohos.data.distributedKVStore`（DEVICE_COLLABORATION，autoSync）——任务进度 / 提醒指令两个键在组网设备间自动同步
  - 权限：`ohos.permission.DISTRIBUTED_DATASYNC`（user_grant）运行时申请，`bundleManager.getBundleInfoForSelf` 取 tokenId 检测状态
- `pages/DevicePage.ets`（设置 → 跨设备协同）：设备列表（类型图标/连接状态）、对端任务进度卡片（实时）、提醒分发（输入内容+分钟 → 广播到在线设备）
- 对端收到提醒指令 → `publishSystemReminder` 创建系统提醒 + Toast（手机输入 → 手表提醒链路）
- ResultPage 每步工具调用 `publishTaskState` 广播进度（失败静默）
- 真机验证：两台设备需同一华为账号 + 蓝牙/WLAN 组网；模拟器无法验证分布式能力

### 5.15 定时任务（v1.2）

- `tools/TaskTools.ets`：`task_create` / `task_list` / `task_cancel` 接上 TaskScheduler 60s 轮询（此前 scheduled_tasks 表无写入方，属死代码）
- 支持一次性（once，下一轮 poll 执行）与周期（interval，每 N 分钟）；执行时由 Agent 自主完成任务并记录结果/耗时
- 示例："每 30 分钟提醒我喝水" → 周期任务 → 每 30 分钟 Agent 自动运行一次
- 注意：暂不支持 cron 表达式（"每天 8 点"需用 interval 近似）；任务执行依赖应用在前台/后台运行

### 5.16 技能系统与自定义提示词（v1.3，OpenClaw 式自由配置）

- **技能分组**：全部工具按组注册（文件管理 / 提醒服务 / 日历与时间 / 天气服务 / 网页搜索 / 记忆笔记 / 定时任务 / MCP 远程工具）
- **自由增删**：设置页技能管理——每个工具独立开关，禁用后：不再发送给 LLM（API 请求体排除）+ 即使被调用也拒绝执行；状态持久化 SQLite（`disabled_tools`）
- **动态提示词**：system prompt = 用户自定义提示词（或默认）+ 按启用状态动态生成的工具清单——禁用技能后提示词同步变化，不会出现"提示词提到已禁用工具"的矛盾
- **AI 提示词编辑器**：设置页新增——自定义角色人设/行为准则，内置 4 个模板（默认助理 / 学习助手 / 效率达人 / 贴心管家），可恢复默认；保存后新对话生效
- **体验**：用户可自由组合能力（如只保留文件+提醒，禁用网页/日历），打造专属个人助手

### 5.17 技能包系统（v1.4，OpenClaw 式分享生态）

- **JSON 技能包格式**（单文件分享）：`{schemaVersion, name, displayName, version, description, author, tags, prompt, requires[], enabled}`
- **预置技能包**（首启自动生成 12 个，升级自动补种新包）：
  - 今日新闻（权威媒体矩阵，领域定向）/ 每日简报 / 会议助手 / 番茄专注 / 天气管家
  - 出行助手 / 健康管家 / 财经速递 / 影视推荐 / 美食菜谱 / 睡前仪式 / 灵感速记
- **导入**：设置页 → 技能包 → 导入（文档选择器选任意 .json，支持从文件管理器/聊天/网盘导入他人分享的包）
- **导出分享**：每个包可导出为 JSON 文件（保存到用户选择位置），发给朋友即可安装
- **启停/删除**：开关即时生效；已启用包的 prompt 注入 system prompt（AI 获得新行为，无需新执行器）
- **安全**：技能包只能引用内置工具（requires 声明依赖），无任意代码执行
- **生态玩法**：社区分享技能包文件 → 用户导入即用，复刻 OpenClaw 的 skill 生态

### 5.18 API 服务大更新（v1.6，API 库 + 服务商预设 + MCP 分页）

- **独立 API 设置页**（设置 → API 服务 / 聊天 → 完整设置）：页内双 Tab——「API 服务」与「MCP 配置」完全分开
- **API 库**：多套配置保存本地（名称/服务商/地址/Key/模型/嵌入Key），保存即启用，点击卡片一键切换（新对话生效），支持编辑/删除（删除当前配置自动落到下一个）
- **服务商预设 ×10**：DeepSeek / OpenAI / 通义千问 / Kimi / 智谱 GLM / SiliconFlow / 百度千帆 / 腾讯混元 / 火山方舟 / Ollama 本地——点选自动填充 Base URL + 默认模型，用户只需填 API Key
- **旧配置自动迁移**：升级后旧 api_key/base_url/model 自动迁为「默认配置」profile，全部旧读取接口（getApiKey/getBaseUrl/getModel/嵌入Key…）从激活 profile 读取，零调用方改动
- **MCP 分页**：MCP 地址配置 + 鸿蒙官方文档一键预设独立成 Tab；聊天页浮层精简（仅 API 字段 + 「完整设置 ›」入口）

### 5.19 对话页三连（v1.7：工具可见 + 思考折叠 + 位置记忆 + 翻页浏览）

- **工具调用可视化**：每条 AI 消息显示「🔧 N 个工具调用」折叠行（默认折叠），展开可看每个工具的：名称、参数、结果摘要、成功/失败状态；底部工具状态栏实时显示正在执行的工具
- **AI 思考折叠**：捕获 DeepSeek 等模型的 reasoning_content（流式 + 非流式全链路），消息内「💭 思考过程」默认折叠，点开看 AI 的思考；思考内容持久化到数据库（新列，自动升级）
- **位置保留**：每个对话的滚动位置 + 页码持久化，从对话列表点进直接回到上次离开的位置
- **翻页对话**：每页 15 条，底部翻页栏「‹ 第 x/y 页 › 最新」——翻页只改变浏览窗口，**对话上下文与 AI 记忆完全保留**（同一对话），配合对话列表管理超长对话非常便捷；发送消息自动跳回最新页

### 5.20 默认非流式（v1.8，设计决策）

- **默认锁定兼容模式（非流式）**：灵犀定位轻型个人助理，单轮任务几秒完成，无需流式；同时规避模拟器/部分网络栈对 SSE 响应的缓冲问题（曾导致"看似无响应"的 15 分钟假死）
- 保留流式实现与自动降级（30 秒无首字节自动切非流式），真机用户可手动开启打字机效果
- 排查经验：模拟器网络栈缓冲 SSE → 物理网络正常（NETSTACK 日志）+ 非流式秒回 = 环境问题而非代码问题

### 5.21 主题系统

- 两套主题（龙虾 `lobster` / 灵犀 `lingxi`）通过 `AppStorage.themeStyle` 全局共享
- 每个页面用 `@StorageLink('themeStyle')` 监听变化
- `getThemeColors(style)` 返回对应的 `ThemeColors` 实例
- 样式值通过 `this.col().textPrimary` 等方法获取

---

## 六、数据流：完整的用户交互示例

```
1. ChatPage 用户输入 "创建一个文件夹叫项目，里面写个readme"
                   ↓
2. ChatPage.sendMessage() → agentCore.runAgent(text, chatId, callback)
                   ↓
3. AgentCore 构建 API 消息列表：
   [system prompt] + [最近30条历史 from SQLite] + [25个工具定义 from ToolRegistry]
                   ↓
4. ApiClient.sendMessage() → POST https://api.deepseek.com/v1/chat/completions
                   ↓
5. LLM 返回 finish_reason="tool_calls":
   tool_calls:[{mkdir: {path:"项目"}}, {write_file: {path:"项目/readme.md", content:"..."}}]
                   ↓
6. AgentCore 遍历 tool_calls：
   ├─ ToolRegistry.executeTool("mkdir", '{"path":"项目"}')
   │   └─ fileIo.mkdir(fullPath, true) → "已创建文件夹: 项目"
   ├─ onEvent({type:"tool_use", name:"mkdir", ...}) → ChatPage 显示工具标签
   ├─ ToolRegistry.executeTool("write_file", '{"path":"项目/readme.md", ...}')
   │   └─ fileIo.openSync + writeSync + closeSync → "已写入 N 字符到..."
   ├─ onEvent({type:"tool_use", name:"write_file", ...})
   │
   ├─ 工具结果回传 API，LLM 继续推理
   └─ LLM 返回 finish_reason="stop" + text="已创建项目文件夹..."
                   ↓
7. AgentCore:
   ├─ onEvent({type:"text", content:"已创建..."}) → ChatPage 气泡更新
   ├─ dbService.storeMessage(assistantMsg) → 存入 SQLite
   └─ onEvent({type:"done"}) → ChatPage 结束加载状态
```

---

## 七、待开发功能清单

### 已完成（v1.0）
- [x] Markdown 渲染（标题 / 列表 / 加粗 / 行内代码）
- [x] 打字机式回复（离线/错误兜底）
- [x] **SSE 真流式回复**（ApiClient 流式解析 + 实时注入，失败/空响应自动回退非流式）
- [x] **网页搜索 + 网页抓取**（Bing 优先 / DDG 兜底）
- [x] **记忆笔记工具**（memory_write / read / list，Markdown 文件）
- [x] **语音输入**（SpeechKit ASR）
- [x] **TTS 播报**（AI 回复朗读）
- [x] **定时提醒**（ReminderAgentKit 系统级倒计时调度 + SQLite 持久化）
- [x] **RAG 知识库**（BGE-M3 向量检索 + 关键词兑底；知识库管理页可查看/重建/删除）
- [x] **MCP 远程工具**（Streamable HTTP 客户端，远程工具以 `mcp_` 前缀接入统一调度）
- [x] **系统日历工具**（calendar_create / calendar_query，CalendarKit + 提前提醒）
- [x] **小艺意图**（JumpFunctionPage 预置意图，小艺唤起 → 自动对话）
- [x] **工作流断点续传**（workflow_runs 落库，带上下文续跑）
- [x] **跨设备协同**（设备发现 + 任务进度实时同步 + 提醒跨设备分发）
- [x] **定时任务**（task_create/list/cancel，TaskScheduler 周期执行 AI 任务）
- [x] **技能系统**（分组启停、动态提示词、SQLite 持久化）
- [x] **自定义 AI 提示词**（人设编辑器 + 4 模板）
- [x] **JSON 技能包**（导入/导出/启停，12 个预置包，文件分享）
- [x] **今日新闻技能**（权威媒体矩阵 site: 搜索、领域定向、偏好记忆）
- [x] **API 服务页**（API 库多配置切换、10 个服务商预设、API/MCP 分 Tab）
- [x] **对话页升级**（工具调用折叠、AI 思考折叠、位置记忆、翻页浏览）
- [x] **默认非流式**（兼容模式锁定，规避模拟器 SSE 缓冲）
- [x] 多会话管理（新建 / 重命名 / 删除 / 列表切换）
- [x] 删除本轮消息（用户 + AI 成对删除）
- [x] 双主题（灵犀浅色 / 龙虾深色）+ 玻璃拟态设计系统
- [x] 文件编辑器（浏览 / 编辑 / 保存文本文件）

### 优先事项（复赛冲刺）
- [ ] 多模态（图片识别）
- [ ] 语音指令直达任务页（语音输入到 ResultPage）
- [ ] 提醒列表持久化（当前提醒存内存，重启丢失）
- [ ] 知识库管理页（查看已索引文件、手动重建索引、嵌入 Key 状态）

### 增强功能
- [ ] 端侧 AI 推理（不再依赖云端 API）
- [ ] 跨设备协同（分布式能力接入；Types.ets 已预留 DeviceInfo 等类型，DISTRIBUTED_DATASYNC 权限已声明）
- [ ] 小艺意图框架接入
- [ ] 记忆笔记与 SettingsPage 记忆管理统一（当前 AI 记忆存文件，设置页存 SQLite KV）
- [ ] RAG 知识库检索
- [ ] MCP 客户端（Streamable HTTP）
- [ ] 工作流断点续传
- [ ] 应用内购买 / API Key 管理平台
- [ ] SettingsPage 技能列表改为从 ToolRegistry 实时读取（当前为静态数据）

---

## 八、参考资源

| 资源 | 用途 |
|------|------|
| **C:\Huawei\nanoclaw-on-openharmony-main** | NanoClaw 鸿蒙移植版（核心 ReAct 模式参考） |
| **https://github.com/anomalyco/openclaw** | 原始 OpenClaw Node.js 实现 |
| **HarmonyOS 开发者文档** | API 用法参考 |

AI 开发者可随时翻阅以上源码仓库理解实现细节。

---

## 九、编码规范速查

| 规则 | 正确 | 错误 |
|------|------|------|
| 类型标注 | `let name: string = ''` | `let name: any` |
| 动态 Schema | `JSON.parse('{"type":"object"}') as Record<string,Object>` | `{'type': 'object'}` |
| 资源引用 | `$r('app.float.spacing_md')` | `'14vp'` |
| 字符串 | `'line1\nline2'` | `` `line1\nline2` `` (跨行) |
| 类成员 | `private value: number = 0` | `private value: number` (未初始化) |
| 接口创建 | `class Foo { ... }` | `new FooInterface()` |
| 索引类型 | `Record<string, Object>` | `Record<string, any>` |
| export 位置 | 文件顶层 | 函数体内 |

---

## 十、竞赛策略分析

### 赛道选择：Agent 创新

灵犀流序申报 **Agent 创新** 方向（作品方向 2），契合点：

- **个人日常生活与陪伴**：在日常生活、工作学习、成长陪伴等场景，让 AI 成为专属伙伴
- **主动服务**：结合时间、天气等上下文信息，让 AI 主动出现在正确时刻
- **自然交互**：纯自然语言驱动，无需手动操作

### 项目完成度评估

| 模块 | 完成度 | 说明 |
|------|--------|------|
| ReAct 推理循环 | 90% | 循环 + 25 本地工具 + MCP 远程工具 + 历史上下文均已实现 |
| 工具系统 | 92% | 本地 20 工具 + MCP 远程工具；缺资源/提示协议扩展 |
| RAG 知识库 | 80% | 向量 + 关键词双模式，逻辑已单测；需真机验证嵌入链路 |
| MCP 客户端 | 85% | 生命周期完整，协议已 mock 验证；需真机联调真实服务器 |
| 对话页面 (ChatPage) | 92% | Markdown + SSE 流式 + 语音输入 + TTS + 多会话 |
| 任务系统 (ResultPage) | 80% | 步进展板 + 进度条 + 计时 + 重新执行 |
| SQLite 持久化 | 85% | 表结构完整，多会话/消息对删除均持久化 |
| 文件管理器 | 75% | 浏览/创建/复制/重命名/删除 + 内置文本编辑器 |
| 多设备协同 | 0% | 未开始（类型与权限已预留） |
| 语音交互 | 60% | ASR 输入 + TTS 播报已实现，需真机验证 |
| 端侧 AI 推理 | 0% | 当前完全依赖云端 API (DeepSeek) |
| 流式回复 (SSE) | 85% | 真流式已实现并通过模拟验证，需真机确认 |
| **整体** | **~75%** | 核心闭环 + UI 打磨 + 高级交互已完成 |

### 评分估算

| 评分项 | 满分 | 自估 | 说明 |
|--------|------|------|------|
| 创新性 | 50 | 33 | Agent 方向竞争少，语音 + 流式已补齐，缺端侧/多设备 |
| 完备度 | 20 | 17 | 20 工具 + 流式 + 语音 + 多会话，演示链路完整 |
| 前景评估 | 20 | 15 | 校园场景真实需求（提醒、文件、天气、搜索、记忆） |
| 规范性 | 10 | 8 | 代码结构清晰，设计系统文档齐全 |
| **基础小计** | **100** | **73** | — |
| 附加分 (HAP可提交) | +20 | +17 | 有可运行 HAP + 源码 + 演示视频 |
| **合计** | **120** | **~90** | — |

### 时间线

| 阶段 | 截止日 | 状态 | 提交要求 |
|------|--------|------|----------|
| **初赛** | 2026-07-26 | ✅ 已提交（文档 + 视频 + HAP/源码 zip） | 创意描述 + 设计稿 + 作品介绍文档(≤800字) + HAP(可选) |
| **复赛** | 2026-09-30 | ⏳ 冲刺中（剩余约 2 个月） | 全部必选：文档 + 视频 + HAP/源码 |
| 总决赛 | 2026-11 | — | 全部必选 + 现场答辩 |

### 初赛（✅ 已完成并提交，2026-07-26）

- 创意描述：`AI Agent 自然语言驱动的个人生活助理`
- 作品说明文档（官方模板 + 交互流程图 + 效果图）
- 演示视频 + HAP/源码 zip（见 `C:\Huawei\submission\`）

### 复赛冲刺规划（2026-08-02 → 2026-09-30，约 2 个月）

**第一优先级（功能补强，直接拉分）**
- [x] ~~真流式回复（SSE 解析，替代打字机模拟）~~ ✅ v0.6 已完成
- [x] ~~网页搜索 + 网页抓取工具（DuckDuckGo）~~ ✅ v0.6 已完成（Bing 优先，DDG 兜底）
- [x] ~~记忆笔记工具（memory_write / memory_read / memory_list，AI 可调）~~ ✅ v0.6 已完成
- [x] ~~语音输入（SpeechKit）+ TTS 播报~~ ✅ v0.6 已完成（需真机验证）

**第二优先级（差异化亮点）**
- [x] ~~RAG 知识库（向量化个人笔记，注入 system prompt）~~ ✅ v0.7 已完成（BGE-M3 + 关键词兑底）
- [x] ~~MCP 客户端（Streamable HTTP，接入远程工具生态）~~ ✅ v0.8 已完成（mock 服务器联调通过）
- [ ] 跨设备协同（分布式数据同步：手机输入 → 手表提醒）

**第三优先级（锦上添花）**
- [ ] 端侧 AI 推理（MindSpore Lite / 小艺开放平台）
- [ ] 小艺意图框架接入
- [ ] 定时提醒延迟触发
- [ ] 多模态（图片识别）
- [ ] 作品上架 AppGallery

### 结论

**初赛已提交，复赛核心功能已完成，冲刺差异化。** Agent 赛道参赛队伍少，ReAct 循环 + 25 个真实工具 + 移动端 UI（Markdown / SSE 流式 / 语音 / TTS / 多会话 / 双主题）已是完整可演示产品。复赛剩余时间按第二优先级补 RAG / MCP / 跨设备，冲击一二等奖有希望。

---

> **文档版本**：v1.8 | **最后更新**：2026-08-08 | **作者**：Lingxi Flow Team
