# 🦞 灵犀流序（Lingxi Flow）

> 运行在 **HarmonyOS NEXT** 上的 AI 智能体（Agent）个人助理应用 —— 用一句话描述需求，AI 自主规划、调用系统工具、一步步帮你完成任务。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

2026 中国高校计算机大赛 · 人工智能创意赛（鸿蒙赛道）参赛作品。

## ✨ 核心功能

- **💬 AI 对话**：接入 DeepSeek / OpenAI / 通义千问 / Kimi / 智谱 GLM 等主流大模型，支持工具调用（Function Calling）
- **🛠 任务编排**：AI 自动规划多步骤任务——"查杭州天气 → 写入今日简报 → 提醒我喝水"一步到位
- **📁 文件管理**：创建 / 读写 / 搜索 / 整理沙盒文件，输出带 `[目录]/[文件]` 标识
- **⏰ 定时提醒**：系统级倒计时提醒（ReminderAgentKit），到点必达；支持周期任务
- **📅 日历日程**：创建 / 查询系统日历，自动提前 10 分钟提醒
- **🗂 技能包系统**：JSON 技能包可导入 / 导出 / 启停 —— 用户自由增删 AI 能力（OpenClaw 式生态）
- **📚 知识库问答**：RAG 检索（BGE-M3 向量嵌入 + 关键词兜底），基于你的资料回答
- **🔍 网页搜索**：内置联网搜索，AI 获取最新信息
- **🎙 语音交互**：语音输入 + 回复朗读
- **📱 多设备协同**：同一华为账号设备间同步任务与提醒
- **🎨 主题系统**：深色龙虾 / 浅色灵犀双主题

## 🚀 构建运行

### 环境要求

- DevEco Studio 5.0+（HarmonyOS NEXT）
- SDK：API 12（compatibleSdkVersion 5.0.0(12)）
- 真机 / 模拟器：HarmonyOS 5.0 及以上

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/<your-name>/lingxi-flow-agent.git

# 2. 用 DevEco Studio 打开项目，等待依赖同步（ohpm）

# 3. 配置签名（上架/真机安装需要）
#    build-profile.json5 中的签名 material 已替换为占位符，
#    请按华为开发者文档生成自己的 .p12/.cer/.p7b 后填入：
#    https://developer.huawei.com/consumer/cn/doc/app/agc-help-devvo-0000001050445824

# 4. 构建
hvigorw assembleHap --mode module -p product=default --no-daemon
```

### 使用 AI 功能

1. 打开应用 → 设置 → API 服务
2. 选择服务商预设（DeepSeek / 通义千问 / Kimi / 智谱 GLM…），填入你的 API Key
3. 返回对话页即可使用全部功能

> 提示：应用默认**非流式**响应（秒级完成，规避部分网络环境对 SSE 的缓冲问题）；可在 API 设置开启流式打字效果。

## 🧠 架构

```
entry/src/main/ets/
├── engine/
│   ├── AgentCore.ets        # ReAct 循环：思考-调用-观察（含 eager 工具并行、失败熔断）
│   ├── ToolRegistry.ets     # 工具注册表：分组、启停、动态提示词
│   ├── DatabaseService.ets  # SQLite 持久化（对话/记忆/任务/知识库）
│   ├── RagService.ets       # 知识库：BGE-M3 向量检索 + 关键词兜底
│   └── TaskScheduler.ets    # 定时任务调度
├── tools/                   # 8 组 25+ 工具（文件/提醒/日历/天气/搜索/记忆/任务）
├── services/
│   ├── ApiClient.ets        # OpenAI 兼容 HTTP 客户端（流式+非流式+自动降级）
│   ├── ConfigService.ets    # API 库：多配置切换 + 服务商预设
│   ├── SkillPackService.ets # JSON 技能包系统（按需注入触发词匹配）
│   ├── McpClient.ets        # MCP 远程工具
│   ├── VoiceService.ets     # 语音识别/合成
│   └── DistributedService.ets # 跨设备协同
└── pages/                   # 对话/设置/API/文件/知识库/设备 页面
```

### 设计亮点

- **eager tool calling**：流式解析中工具参数一闭合立即执行，与 LLM 输出并行（端到端提速 ~50%）
- **动态系统提示词**：工具清单按启用状态生成；技能包按触发词**按需注入**（请求体瘦身 3 倍）
- **提醒准点**：`create_reminder(datetime)` 绝对时间参数，工具执行时刻换算延迟，慢网络也准时
- **自适应降级**：流式 30s 无首字节自动切非流式；排队超时自动去掉 thinking 参数重试
- **沙盒安全**：技能包仅声明式（无任意代码执行），用户可放心导入

## 📄 文档

- [PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md) - 项目总览与版本记录
- [软件说明.md](docs/软件说明.md) - 功能使用说明
- [开发经验记录.md](docs/开发经验记录.md) - 开发踩坑记录（模拟器 SSE 缓冲等）

## 📜 License

[MIT](LICENSE) © 2026 Lingxi Flow Team

> 本项目为个人参赛作品，与任何公司/组织无关。AI 回复由大模型生成，仅供参考。
