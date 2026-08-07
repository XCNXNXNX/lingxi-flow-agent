// AgentCore - ReAct loop with tool calling
// Based on NanoClaw's container-runner + agent-runner pattern
// Manages: conversation history, API calls, tool execution, message persistence
import { Logger } from '../utils/Logger'
import { generateId } from '../utils/TextFormatter'
import { common } from '@kit.AbilityKit'
import { ApiClient } from '../services/ApiClient'
import { ToolRegistry } from './ToolRegistry'
import { dbService } from './DatabaseService'
import { configService } from '../services/ConfigService'
import { ragService } from './RagService'
import { skillPackService } from '../services/SkillPackService'
import { registerFileTools, initFileTools } from '../tools/FileTools'
import { registerReminderTools, initReminderTools } from '../tools/ReminderTools'
import { registerCalendarTools, initCalendarTools } from '../tools/CalendarTools'
import { registerWeatherTools } from '../tools/WeatherTools'
import { registerWebTools } from '../tools/WebTools'
import { registerMemoryTools, initMemoryTools } from '../tools/MemoryTools'
import { registerTaskTools } from '../tools/TaskTools'
import { mcpClient } from '../services/McpClient'
import {
  AgentEvent,
  AgentTextEvent,
  AgentStreamEvent,
  AgentReasoningEvent,
  AgentToolUseEvent,
  AgentErrorEvent,
  AgentDoneEvent,
  ApiChoice,
  ApiConfig,
  ApiMessage,
  ApiResponse,
  ChatMessage,
  ToolCall,
  ToolCallFunction,
  ToolCallRecord,
  ToolDefinition,
  ToolResult
} from '../model/Types'

const MAX_ITERATIONS: number = 15
const CONTEXT_WINDOW: number = 30

// 基础提示词：角色 + 使用引导（工具清单由注册表动态生成）
const DEFAULT_BASE_PROMPT: string = `你是灵犀(Lingxi Flow)，运行在HarmonyOS上的智能个人助理。

区分提醒与日程：
- 用户说"X分钟后/半小时后提醒我" → 用 create_reminder（minutes 参数）
- 用户说"明天下午3点开会/安排日程" → 用 calendar_create：先 get_current_date/get_current_time 确定当前时间，算出目标时间的毫秒时间戳作为 start_time；若用户说的是相对时间（"1小时后"）则用 minutes_from_now

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

const TOOL_PROMPT_PREFIX: string = '\n\n当前你可使用的工具如下（按技能分组）：\n'

export class AgentCore {
  private apiClient: ApiClient | null = null
  private toolRegistry: ToolRegistry = new ToolRegistry()
  private initialized: boolean = false

  async init(context: common.UIAbilityContext, filesDir: string): Promise<void> {
    if (this.initialized) {
      return
    }

    initFileTools(filesDir)
    await initReminderTools()
    initMemoryTools(filesDir)
    initCalendarTools(context)
    await skillPackService.init(context, filesDir)
    registerFileTools(this.toolRegistry)
    registerReminderTools(this.toolRegistry)
    registerCalendarTools(this.toolRegistry)
    registerWeatherTools(this.toolRegistry)
    registerWebTools(this.toolRegistry)
    registerMemoryTools(this.toolRegistry)
    registerTaskTools(this.toolRegistry)
    try {
      await mcpClient.initAndRegister(this.toolRegistry)
    } catch (e) {
      Logger.warn('AgentCore', 'MCP init failed: ' + (e as Error).message)
    }
    await this.toolRegistry.loadDisabledState()
    Logger.info('AgentCore', 'initialized with ' + this.toolRegistry.getToolCount() +
      ' tools (' + this.toolRegistry.getEnabledToolCount() + ' enabled)')

    this.initialized = true
    Logger.info('AgentCore', 'initialized with ' + this.toolRegistry.getToolDefinitions().length + ' tools')
  }

  async hasApiKey(): Promise<boolean> {
    return await configService.hasApiKey()
  }

  getToolRegistry(): ToolRegistry {
    return this.toolRegistry
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

      // Build API messages array with user prompt + dynamic tool list + RAG context
      const apiMessages: ApiMessage[] = []
      let systemContent: string = await configService.getSystemPrompt()
      if (systemContent.length === 0) {
        systemContent = DEFAULT_BASE_PROMPT
      }
      systemContent = systemContent + TOOL_PROMPT_PREFIX + this.toolRegistry.getEnabledToolSummary()
      const packsPrompt: string = skillPackService.getEnabledPacksPrompt()
      if (packsPrompt.length > 0) {
        systemContent = systemContent + '\n\n' + packsPrompt
      }
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
          const toolRecords: ToolCallRecord[] | undefined = msg.toolCalls
          if (toolRecords && toolRecords.length > 0) {
            // Rebuild assistant tool_calls + tool result messages so the model
            // keeps full tool context across multi-turn conversations
            const apiToolCalls: ToolCall[] = []
            for (let t: number = 0; t < toolRecords.length; t++) {
              const rec: ToolCallRecord = toolRecords[t]
              const callId: string = 'call_' + msg.id + '_' + t
              const fn: ToolCallFunction = { name: rec.name, arguments: rec.input }
              apiToolCalls.push({ id: callId, type: 'function', function: fn })
            }
            apiMessages.push({ role: 'assistant', content: msg.content || null, toolCalls: apiToolCalls })
            for (let t2: number = 0; t2 < toolRecords.length; t2++) {
              const rec2: ToolCallRecord = toolRecords[t2]
              apiMessages.push({
                role: 'tool',
                content: rec2.result,
                toolCallId: 'call_' + msg.id + '_' + t2
              })
            }
          } else {
            apiMessages.push({ role: 'assistant', content: msg.content || '' })
          }
        }
      }

      // Get enabled tool definitions
      const allTools: ToolDefinition[] = this.toolRegistry.getEnabledToolDefinitions()

      // ReAct loop
      let iterations: number = 0
      let consecutiveToolErrors: number = 0
      const allToolRecords: ToolCallRecord[] = []

      while (iterations < MAX_ITERATIONS) {
        iterations++
        Logger.info('AgentCore', 'ReAct iteration ' + iterations + '/' + MAX_ITERATIONS)

        let response: ApiResponse
        if (useStream) {
          try {
            response = await client.sendMessageStream(apiMessages, allTools,
              (text: string, reason: string, reasoningText: string): void => {
                if (reasoningText.length > 0) {
                  const rEvent: AgentReasoningEvent = { type: 'reasoning', content: reasoningText }
                  onEvent(rEvent)
                }
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
        // Report thinking (reasoning_content) if the provider returned it
        if (assistantMessage.reasoning && assistantMessage.reasoning.length > 0) {
          const rEvent: AgentReasoningEvent = { type: 'reasoning', content: assistantMessage.reasoning }
          onEvent(rEvent)
        }

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

          // Execute tool calls IN PARALLEL (they are independent - model returns them
          // together). Serial execution multiplied latency per tool (web searches etc).
          const toolCallList: ToolCall[] = assistantMessage.toolCalls
          const execPromises: Promise<ToolResult>[] = []
          for (let p: number = 0; p < toolCallList.length; p++) {
            const tc: ToolCall = toolCallList[p]
            Logger.info('AgentCore', 'Tool: ' + tc.function.name + '(' + tc.function.arguments + ')')
            execPromises.push(this.toolRegistry.executeTool(tc.function.name, tc.function.arguments, tc.id))
          }
          const execResults: ToolResult[] = await Promise.all(execPromises)

          for (let i: number = 0; i < execResults.length; i++) {
            const toolCall: ToolCall = toolCallList[i]
            const toolName: string = toolCall.function.name
            const result: ToolResult = execResults[i]

            // Circuit breaker: 3 consecutive tool failures means something is wrong -
            // stop looping and report instead of burning minutes of LLM round-trips
            if (result.isError) {
              consecutiveToolErrors++
            } else {
              consecutiveToolErrors = 0
            }
            if (consecutiveToolErrors >= 3) {
              const breakerMsg: string = '连续 ' + consecutiveToolErrors + ' 次工具调用失败（最近: ' + toolName + '），已停止尝试以避免空转。请检查路径/参数描述是否正确后重试。'
              Logger.warn('AgentCore', breakerMsg)
              const breakerEvent: AgentTextEvent = { type: 'text', content: breakerMsg }
              onEvent(breakerEvent)
              const breakerRecord: ToolCallRecord = {
                name: toolName,
                input: toolCall.function.arguments,
                result: result.content,
                isError: true
              }
              allToolRecords.push(breakerRecord)
              const breakerMsg2: ChatMessage = {
                id: generateId(),
                chatId: chatId,
                sender: 'assistant',
                senderName: 'Lingxi',
                content: breakerMsg,
                timestamp: new Date().toISOString(),
                isFromMe: false,
                toolCalls: allToolRecords
              }
              await dbService.storeMessage(breakerMsg2)
              const breakerDone: AgentDoneEvent = { type: 'done' }
              onEvent(breakerDone)
              return
            }

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
