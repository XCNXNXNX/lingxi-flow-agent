// AgentCore - ReAct loop with tool calling
// Based on NanoClaw's container-runner + agent-runner pattern
// Manages: conversation history, API calls, tool execution, message persistence
import { Logger } from '../utils/Logger'
import { generateId } from '../utils/TextFormatter'
import { ApiClient } from '../services/ApiClient'
import { ToolRegistry } from './ToolRegistry'
import { dbService } from './DatabaseService'
import { configService } from '../services/ConfigService'
import { ragService } from './RagService'
import { registerFileTools, initFileTools } from '../tools/FileTools'
import { registerReminderTools, initReminderTools } from '../tools/ReminderTools'
import { registerCalendarTools } from '../tools/CalendarTools'
import { registerWeatherTools } from '../tools/WeatherTools'
import { registerWebTools } from '../tools/WebTools'
import { registerMemoryTools, initMemoryTools } from '../tools/MemoryTools'
import { mcpClient } from '../services/McpClient'
import {
  AgentEvent,
  AgentTextEvent,
  AgentStreamEvent,
  AgentToolUseEvent,
  AgentErrorEvent,
  AgentDoneEvent,
  ApiChoice,
  ApiConfig,
  ApiMessage,
  ApiResponse,
  ChatMessage,
  ToolCall,
  ToolCallRecord,
  ToolDefinition,
  ToolResult
} from '../model/Types'

const MAX_ITERATIONS: number = 15
const CONTEXT_WINDOW: number = 30

const SYSTEM_PROMPT: string = `你是灵犀(Lingxi Flow)，运行在HarmonyOS上的智能个人助理。

你可以使用以下工具：
- 文件操作：创建目录、写入文件、读取文件、列出目录、删除文件、搜索文件、复制文件、粘贴文件
- 提醒管理：创建提醒、列出提醒、取消提醒
- 时间日期：获取当前时间、日期、星期
- 天气查询：查询指定城市的天气
- 网页搜索：搜索互联网信息（web_search）、抓取网页正文（web_fetch）
- 记忆笔记：把重要信息写入长期记忆（memory_write），读取记忆（memory_read），列出记忆（memory_list）

当用户需要计划或提醒时，你应该主动：
1. 使用 get_current_date 确认今天日期
2. 使用 get_current_time 确认现在时间
3. 使用 get_weather 查询天气（当需要时）
4. 使用 create_reminder 创建提醒：若用户说"X分钟后提醒我..."，把 X 作为 minutes 参数传入；若用户说具体时间（如"下午3点"），先用 get_current_time 计算当前与目标时间的分钟差，再作为 minutes 传入；若用户没提时间，默认 minutes=60
5. 最终用关心的语气总结，体现你为用户的周全考虑

当用户问到新闻、百科、时效性信息时，应使用 web_search 查询，需要细节时再用 web_fetch 抓取正文。
当用户告诉你他的偏好、重要事项、需要长期记住的信息时，应使用 memory_write 保存；下次相关对话时先 memory_read 回顾。
使用工具时请逐步思考，一次只调用必要的工具。完成后请总结你所做的事情。
请用中文回复，语气温暖体贴，像家人一样关心用户。`

export class AgentCore {
  private apiClient: ApiClient | null = null
  private toolRegistry: ToolRegistry = new ToolRegistry()
  private initialized: boolean = false

  async init(filesDir: string): Promise<void> {
    if (this.initialized) {
      return
    }

    initFileTools(filesDir)
    initReminderTools()
    initMemoryTools(filesDir)
    registerFileTools(this.toolRegistry)
    registerReminderTools(this.toolRegistry)
    registerCalendarTools(this.toolRegistry)
    registerWeatherTools(this.toolRegistry)
    registerWebTools(this.toolRegistry)
    registerMemoryTools(this.toolRegistry)
    try {
      await mcpClient.initAndRegister(this.toolRegistry)
    } catch (e) {
      Logger.warn('AgentCore', 'MCP init failed: ' + (e as Error).message)
    }

    this.initialized = true
    Logger.info('AgentCore', 'initialized with ' + this.toolRegistry.getToolDefinitions().length + ' tools')
  }

  async hasApiKey(): Promise<boolean> {
    return await configService.hasApiKey()
  }

  private async ensureApiClient(): Promise<ApiClient> {
    const config: ApiConfig = await configService.getApiConfig()
    if (config.apiKey.length === 0) {
      throw new Error('请先配置API Key')
    }

    if (this.apiClient) {
      this.apiClient.updateConfig(config)
    } else {
      this.apiClient = new ApiClient(config)
    }

    return this.apiClient
  }

  async runAgent(
    userMessage: string,
    chatId: string,
    onEvent: (event: AgentEvent) => void
  ): Promise<void> {
    await this.runLoop(userMessage, chatId, onEvent, false)
  }

  // Streaming variant: emits 'stream' events with partial text as it arrives
  async runAgentStream(
    userMessage: string,
    chatId: string,
    onEvent: (event: AgentEvent) => void
  ): Promise<void> {
    await this.runLoop(userMessage, chatId, onEvent, true)
  }

  private async runLoop(
    userMessage: string,
    chatId: string,
    onEvent: (event: AgentEvent) => void,
    useStream: boolean
  ): Promise<void> {
    try {
      const client: ApiClient = await this.ensureApiClient()

      await dbService.ensureChat(chatId, '对话')

      // Store user message
      const userMsg: ChatMessage = {
        id: generateId(),
        chatId: chatId,
        sender: 'user',
        senderName: 'User',
        content: userMessage,
        timestamp: new Date().toISOString(),
        isFromMe: true
      }
      await dbService.storeMessage(userMsg)

      // Load conversation history
      const history: ChatMessage[] = await dbService.getMessages(chatId, CONTEXT_WINDOW)

      // Build API messages array with RAG-augmented system prompt
      const apiMessages: ApiMessage[] = []
      let systemContent: string = SYSTEM_PROMPT
      try {
        const ragChunks: string[] = await ragService.retrieve(userMessage, 3)
        if (ragChunks.length > 0) {
          systemContent = systemContent +
            '\n\n【知识库参考】以下是你的知识库中与用户问题相关的内容，回答时优先参考：\n' +
            ragChunks.join('\n---\n') +
            '\n【知识库结束】若上述内容与问题无关，请忽略。'
        }
      } catch (_e) {
        // RAG failure must never break the chat
      }
      apiMessages.push({ role: 'system', content: systemContent })

      for (let i: number = 0; i < history.length; i++) {
        const msg: ChatMessage = history[i]
        if (msg.isFromMe) {
          apiMessages.push({ role: 'user', content: msg.content })
        } else {
          apiMessages.push({ role: 'assistant', content: msg.content || '' })
        }
      }

      // Get tool definitions
      const allTools: ToolDefinition[] = this.toolRegistry.getToolDefinitions()

      // ReAct loop
      let iterations: number = 0
      const allToolRecords: ToolCallRecord[] = []

      while (iterations < MAX_ITERATIONS) {
        iterations++
        Logger.info('AgentCore', 'ReAct iteration ' + iterations + '/' + MAX_ITERATIONS)

        let response: ApiResponse
        if (useStream) {
          try {
            response = await client.sendMessageStream(apiMessages, allTools,
              (text: string, reason: string): void => {
                if (reason.length === 0) {
                  const streamEvent: AgentStreamEvent = { type: 'stream', content: text }
                  onEvent(streamEvent)
                }
              })
            // Safety: some providers mishandle stream:true and return empty - fall back to non-streaming
            const msg: ApiMessage = response.choices[0].message
            const hasContent: boolean = (msg.content || '').length > 0
            const hasToolCalls: boolean = msg.toolCalls !== undefined && msg.toolCalls.length > 0
            if (!hasContent && !hasToolCalls) {
              Logger.warn('AgentCore', 'stream returned empty, retrying non-stream')
              response = await client.sendMessage(apiMessages, allTools)
            }
          } catch (e) {
            Logger.warn('AgentCore', 'stream failed, retrying non-stream: ' + (e as Error).message)
            response = await client.sendMessage(apiMessages, allTools)
          }
        } else {
          response = await client.sendMessage(apiMessages, allTools)
        }
        const choice: ApiChoice = response.choices[0]
        const assistantMessage: ApiMessage = choice.message

        Logger.info('AgentCore', 'finish_reason=' + choice.finishReason + ' tokens=' + response.usage.totalTokens)

        // Check if model wants to call tools
        if (choice.finishReason === 'tool_calls' && assistantMessage.toolCalls) {
          // Add assistant tool_call request to history
          const assistApiMsg: ApiMessage = {
            role: 'assistant',
            content: assistantMessage.content,
            toolCalls: assistantMessage.toolCalls
          }
          apiMessages.push(assistApiMsg)

          // Execute each tool call
          for (let i: number = 0; i < assistantMessage.toolCalls.length; i++) {
            const toolCall: ToolCall = assistantMessage.toolCalls[i]
            const toolName: string = toolCall.function.name
            Logger.info('AgentCore', 'Tool: ' + toolName + '(' + toolCall.function.arguments + ')')

            const result: ToolResult = await this.toolRegistry.executeTool(
              toolName,
              toolCall.function.arguments,
              toolCall.id
            )

            // Report to UI
            const toolEvent: AgentToolUseEvent = {
              type: 'tool_use',
              name: toolName,
              input: toolCall.function.arguments,
              result: result.content,
              isError: result.isError
            }
            onEvent(toolEvent)

            // Record for storage
            const record: ToolCallRecord = {
              name: toolName,
              input: toolCall.function.arguments,
              result: result.content,
              isError: result.isError
            }
            allToolRecords.push(record)

            // Add tool result to API context
            const toolMsg: ApiMessage = {
              role: 'tool',
              content: result.content,
              toolCallId: toolCall.id
            }
            apiMessages.push(toolMsg)
          }

          continue
        }

        // Model is done - return final text
        const textContent: string = assistantMessage.content || ''

        if (textContent.length > 0) {
          const textEvent: AgentTextEvent = { type: 'text', content: textContent }
          onEvent(textEvent)
        }

        // Save assistant response
        const assistantMsg: ChatMessage = {
          id: generateId(),
          chatId: chatId,
          sender: 'assistant',
          senderName: 'Lingxi',
          content: textContent,
          timestamp: new Date().toISOString(),
          isFromMe: false,
          toolCalls: allToolRecords.length > 0 ? allToolRecords : undefined
        }
        await dbService.storeMessage(assistantMsg)

        const doneEvent: AgentDoneEvent = { type: 'done' }
        onEvent(doneEvent)
        return
      }

      // Max iterations reached
      const maxMsg: string = '[达到最大工具调用轮次 ' + MAX_ITERATIONS + ']'
      const maxEvent: AgentTextEvent = { type: 'text', content: maxMsg }
      onEvent(maxEvent)

      const overflowMsg: ChatMessage = {
        id: generateId(),
        chatId: chatId,
        sender: 'assistant',
        senderName: 'Lingxi',
        content: maxMsg,
        timestamp: new Date().toISOString(),
        isFromMe: false,
        toolCalls: allToolRecords.length > 0 ? allToolRecords : undefined
      }
      await dbService.storeMessage(overflowMsg)

      const doneEvent2: AgentDoneEvent = { type: 'done' }
      onEvent(doneEvent2)

    } catch (e) {
      const errorMsg: string = (e as Error).message || String(e)
      Logger.error('AgentCore', 'Error: ' + errorMsg)
      const errEvent: AgentErrorEvent = { type: 'error', error: errorMsg }
      onEvent(errEvent)
    }
  }

  getFallbackReply(input: string): string {
    const lower: string = input.toLowerCase()
    if (lower.includes('你好') || lower.includes('hi') || lower.includes('hello')) {
      return '你好！我是灵犀，你的鸿蒙AI助手。说说你想做什么？'
    }
    if (lower.includes('你是谁') || lower.includes('帮助') || lower.includes('功能')) {
      return '我是灵犀，运行在HarmonyOS上的AI助手。\n\n我能帮你：\n- 创建和管理文件/文件夹\n- 读写文件内容\n- 设置提醒\n- 对话交流\n\n配置AI API后可解锁更强能力。'
    }
    if (lower.includes('谢谢') || lower.includes('感谢')) {
      return '不客气！有需要随时找我。'
    }
    return '收到！配置AI API后我能更好地理解你。点击右上角「API」设置。'
  }
}

export const agentCore: AgentCore = new AgentCore()
