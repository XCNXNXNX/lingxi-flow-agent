// ApiClient - OpenAI-compatible HTTP client for LLM API
// Fixed: uses object literals instead of 'new InterfaceName()' which is illegal in ArkTS
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'
import { ApiConfig, ApiMessage, ApiResponse, ApiChoice, ApiUsage, ToolDefinition, ToolCall, ToolCallFunction } from '../model/Types'

interface ApiRequestBody {
  model: string
  messages: ApiRequestMessage[]
  tools?: ApiRequestTool[]
  max_tokens: number
  temperature: number
  stream: boolean
  thinking?: ThinkingControl
}

interface ThinkingControl {
  type: string
}

interface ApiRequestMessage {
  role: string
  content?: string | null
  tool_calls?: ApiRequestToolCall[]
  tool_call_id?: string
}

interface ApiRequestToolCall {
  id: string
  type: string
  function: ApiRequestFunction
}

interface ApiRequestFunction {
  name: string
  arguments: string
}

interface ApiRequestTool {
  type: string
  function: ApiRequestToolFunction
}

interface ApiRequestToolFunction {
  name: string
  description: string
  parameters: Record<string, Object>
}

interface ApiResponseBody {
  id: string
  choices: ApiResponseChoice[]
  usage: ApiResponseUsage
  error?: ApiResponseError
}

interface ApiResponseChoice {
  index: number
  message: ApiResponseMessage
  finish_reason: string
}

interface ApiResponseMessage {
  role: string
  content: string | null
  reasoning_content?: string | null
  tool_calls?: ApiResponseToolCall[]
}

interface ApiResponseToolCall {
  id: string
  type: string
  function: ApiResponseFunction
}

interface ApiResponseFunction {
  name: string
  arguments: string
}

interface ApiResponseUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

interface ApiResponseError {
  message: string
  type: string
}

// --- SSE streaming types ---

interface ApiStreamChunk {
  choices?: ApiStreamChoice[]
}

interface ApiStreamChoice {
  index: number
  delta?: ApiStreamDelta
  message?: ApiStreamMessage
  finish_reason?: string | null
}

interface ApiStreamMessage {
  content?: string | null
}

interface ApiStreamDelta {
  content?: string | null
  reasoning_content?: string | null
  tool_calls?: ApiStreamToolCallDelta[]
}

interface ApiStreamToolCallDelta {
  index: number
  id?: string
  type?: string
  function?: ApiStreamFunctionDelta
}

interface ApiStreamFunctionDelta {
  name?: string
  arguments?: string
}

interface ModelsResponseData {
  data: ModelsItem[]
}

interface ModelsItem {
  id: string
}

async function sleepMs(ms: number): Promise<void> {
  const p: Promise<void> = new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms)
  })
  return p
}

export class ApiClient {
  private config: ApiConfig

  constructor(config: ApiConfig) {
    this.config = config
  }

  updateConfig(config: ApiConfig): void {
    this.config = config
  }

  async sendMessage(messages: ApiMessage[], tools?: ToolDefinition[]): Promise<ApiResponse> {
    const url: string = this.config.baseUrl + '/chat/completions'

    const apiMessages: ApiRequestMessage[] = this.buildRequestMessages(messages)
    const body: ApiRequestBody = this.buildRequestBody(apiMessages, tools, false)

    const httpRequest: http.HttpRequest = http.createHttp()
    let retries: number = 0
    const maxRetries: number = 3

    while (retries <= maxRetries) {
      try {
        Logger.info('ApiClient', 'req model=' + this.config.model + ' msgs=' + messages.length + ' tools=' + (tools ? tools.length : 0))

        const response: http.HttpResponse = await httpRequest.request(url, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + this.config.apiKey
          },
          extraData: JSON.stringify(body),
          connectTimeout: 30000,
          readTimeout: 120000
        })

        if (response.responseCode === 429) {
          retries++
          if (retries > maxRetries) {
            throw new Error('Rate limited: too many requests')
          }
          const waitMs: number = Math.pow(2, retries) * 1000
          Logger.warn('ApiClient', 'rate limited, retry ' + retries + ', wait ' + waitMs + 'ms')
          await sleepMs(waitMs)
          continue
        }

        if (response.responseCode !== 200) {
          throw new Error('API error ' + response.responseCode + ': ' + (response.result as string))
        }

        const result: ApiResponseBody = JSON.parse(response.result as string) as ApiResponseBody
        if (result.error) {
          throw new Error('API error: ' + result.error.message)
        }

        httpRequest.destroy()
        return this.parseResponse(result)
      } catch (e) {
        if (retries >= maxRetries) {
          httpRequest.destroy()
          throw e as Error
        }
        retries++
        Logger.warn('ApiClient', 'request failed, retry ' + retries + ': ' + (e as Error).message)
        const waitMs: number = Math.pow(2, retries) * 1000
        await sleepMs(waitMs)
      }
    }

    httpRequest.destroy()
    throw new Error('API request failed after max retries')
  }

  private buildRequestMessages(messages: ApiMessage[]): ApiRequestMessage[] {
    const apiMessages: ApiRequestMessage[] = []
    for (let i: number = 0; i < messages.length; i++) {
      const m: ApiMessage = messages[i]
      const msg: ApiRequestMessage = { role: m.role }
      if (m.content !== undefined && m.content !== null) {
        msg.content = m.content
      }
      if (m.toolCalls && m.toolCalls.length > 0) {
        const tcList: ApiRequestToolCall[] = []
        for (let j: number = 0; j < m.toolCalls.length; j++) {
          const tc: ToolCall = m.toolCalls[j]
          const fn: ApiRequestFunction = {
            name: tc.function.name,
            arguments: tc.function.arguments
          }
          const reqTc: ApiRequestToolCall = {
            id: tc.id,
            type: tc.type,
            function: fn
          }
          tcList.push(reqTc)
        }
        msg.tool_calls = tcList
      }
      if (m.toolCallId) {
        msg.tool_call_id = m.toolCallId
      }
      apiMessages.push(msg)
    }
    return apiMessages
  }

  private buildRequestBody(apiMessages: ApiRequestMessage[], tools: ToolDefinition[] | undefined, stream: boolean): ApiRequestBody {
    const body: ApiRequestBody = {
      model: this.config.model,
      messages: apiMessages,
      max_tokens: this.config.maxTokens,
      temperature: this.config.temperature,
      stream: stream
    }
    // DeepSeek API defaults to thinking mode (enabled) - each request spends minutes
    // on hidden reasoning before answering. Disable it for non-reasoner models so
    // simple questions get instant replies (deepseek-reasoner keeps thinking on purpose).
    const isDeepSeek: boolean = this.config.baseUrl.indexOf('deepseek') >= 0
    const isReasoner: boolean = this.config.model.indexOf('reasoner') >= 0
    if (isDeepSeek && !isReasoner) {
      const thinkingCtl: ThinkingControl = { type: 'disabled' }
      body.thinking = thinkingCtl
    }
    if (tools && tools.length > 0) {
      const toolList: ApiRequestTool[] = []
      for (let i: number = 0; i < tools.length; i++) {
        const t: ToolDefinition = tools[i]
        const fn: ApiRequestToolFunction = {
          name: t.function.name,
          description: t.function.description,
          parameters: t.function.parameters as Record<string, Object>
        }
        const reqTool: ApiRequestTool = {
          type: t.type,
          function: fn
        }
        toolList.push(reqTool)
      }
      body.tools = toolList
    }
    return body
  }

  /**
   * Streaming (SSE) chat completion.
   * onDelta(text, finishReason, reasoningText) is called on every delta with accumulated text.
   * Resolves with the full ApiResponse once the stream ends ([DONE] or dataEnd).
   */
  async sendMessageStream(
    messages: ApiMessage[],
    tools: ToolDefinition[] | undefined,
    onDelta: (text: string, finishReason: string, reasoningText: string) => void
  ): Promise<ApiResponse> {
    const url: string = this.config.baseUrl + '/chat/completions'
    const apiMessages: ApiRequestMessage[] = this.buildRequestMessages(messages)
    const body: ApiRequestBody = this.buildRequestBody(apiMessages, tools, true)
    const httpRequest: http.HttpRequest = http.createHttp()
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8')
    const toolCallMap: Map<number, ToolCall> = new Map()

    let buffer: string = ''
    let accText: string = ''
    let accReasoning: string = ''
    let finishReason: string = ''
    let resolved: boolean = false
    let lastDataAt: number = Date.now()

    return new Promise<ApiResponse>((resolve: (resp: ApiResponse) => void, reject: (err: Error) => void): void => {
      // Watchdog: if no data arrives for 90s, fail instead of hanging forever
      const watchdog: number = setInterval((): void => {
        if (resolved) {
          clearInterval(watchdog)
          return
        }
        if (Date.now() - lastDataAt > 90000) {
          resolved = true
          clearInterval(watchdog)
          httpRequest.destroy()
          reject(new Error('流式响应超时（90 秒无数据）'))
        }
      }, 15000)

      const finalize = (): void => {
        if (resolved) {
          return
        }
        resolved = true
        clearInterval(watchdog)
        httpRequest.destroy()
        const toolCalls: ToolCall[] = []
        toolCallMap.forEach((tc: ToolCall): void => {
          toolCalls.push(tc)
        })
        const apiMessage: ApiMessage = {
          role: 'assistant',
          content: accText,
          reasoning: accReasoning.length > 0 ? accReasoning : undefined,
          toolCalls: toolCalls.length > 0 ? toolCalls : undefined
        }
        const apiChoice: ApiChoice = {
          index: 0,
          message: apiMessage,
          finishReason: finishReason
        }
        const apiUsage: ApiUsage = {
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0
        }
        const apiResponse: ApiResponse = {
          id: 'stream',
          choices: [apiChoice],
          usage: apiUsage
        }
        resolve(apiResponse)
      }

      httpRequest.on('dataReceive', (data: ArrayBuffer): void => {
        lastDataAt = Date.now()
        buffer += decoder.decodeWithStream(new Uint8Array(data))
        let idx: number = buffer.indexOf('\n')
        while (idx >= 0) {
          const line: string = buffer.substring(0, idx).trim()
          buffer = buffer.substring(idx + 1)
          if (line.startsWith('data:')) {
            const payload: string = line.substring(5).trim()
            if (payload === '[DONE]') {
              finalize()
              return
            }
            try {
              const chunk: ApiStreamChunk = JSON.parse(payload) as ApiStreamChunk
              if (!chunk.choices || chunk.choices.length === 0) {
                idx = buffer.indexOf('\n')
                continue
              }
              const choice: ApiStreamChoice = chunk.choices[0]
              if (choice.finish_reason && choice.finish_reason.length > 0) {
                finishReason = choice.finish_reason
              }
              const delta: ApiStreamDelta | undefined = choice.delta
              if (delta) {
                if (delta.reasoning_content && delta.reasoning_content.length > 0) {
                  accReasoning += delta.reasoning_content
                }
                if (delta.content && delta.content.length > 0) {
                  accText += delta.content
                  onDelta(accText, finishReason, accReasoning)
                }
                if (delta.tool_calls && delta.tool_calls.length > 0) {
                  this.accumulateToolCall(toolCallMap, delta.tool_calls)
                }
              } else if (choice.message && choice.message.content && choice.message.content.length > 0) {
                // Non-standard provider: full message in one chunk instead of deltas
                accText = choice.message.content
                onDelta(accText, finishReason, accReasoning)
              }
            } catch (_e) {
              // ignore malformed frames (keep-alive etc.)
            }
          }
          idx = buffer.indexOf('\n')
        }
      })

      httpRequest.on('dataEnd', (): void => {
        finalize()
      })

      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + this.config.apiKey
        },
        extraData: JSON.stringify(body),
        connectTimeout: 30000,
        readTimeout: 120000
      }).then((response: http.HttpResponse): void => {
        if (response.responseCode !== 200) {
          if (resolved) {
            return
          }
          resolved = true
          httpRequest.destroy()
          reject(new Error('API error ' + response.responseCode + ': ' + (response.result as string)))
        }
      }).catch((e: Error): void => {
        if (resolved) {
          return
        }
        resolved = true
        httpRequest.destroy()
        reject(e as Error)
      })
    })
  }

  // Accumulate streaming tool_call deltas (fragments arrive across chunks)
  private accumulateToolCall(map: Map<number, ToolCall>, deltas: ApiStreamToolCallDelta[]): void {
    for (let i: number = 0; i < deltas.length; i++) {
      const d: ApiStreamToolCallDelta = deltas[i]
      let tc: ToolCall | undefined = map.get(d.index)
      if (!tc) {
        tc = {
          id: d.id || '',
          type: 'function',
          function: { name: '', arguments: '' }
        }
        map.set(d.index, tc)
      }
      if (d.id && d.id.length > 0) {
        tc.id = d.id
      }
      if (d.function) {
        if (d.function.name && d.function.name.length > 0) {
          tc.function.name += d.function.name
        }
        if (d.function.arguments && d.function.arguments.length > 0) {
          tc.function.arguments += d.function.arguments
        }
      }
    }
  }

  private parseResponse(body: ApiResponseBody): ApiResponse {
    const choice: ApiResponseChoice = body.choices[0]
    const message: ApiResponseMessage = choice.message

    let toolCalls: ToolCall[] | undefined = undefined
    if (message.tool_calls && message.tool_calls.length > 0) {
      toolCalls = []
      for (let i: number = 0; i < message.tool_calls.length; i++) {
        const tc: ApiResponseToolCall = message.tool_calls[i]
        const fn: ToolCallFunction = {
          name: tc.function.name,
          arguments: tc.function.arguments
        }
        const toolCall: ToolCall = {
          id: tc.id,
          type: 'function',
          function: fn
        }
        toolCalls.push(toolCall)
      }
    }

    const apiMessage: ApiMessage = {
      role: message.role as ('system' | 'user' | 'assistant' | 'tool'),
      content: message.content,
      reasoning: message.reasoning_content && message.reasoning_content.length > 0 ? message.reasoning_content : undefined,
      toolCalls: toolCalls
    }

    const apiChoice: ApiChoice = {
      index: choice.index,
      message: apiMessage,
      finishReason: choice.finish_reason
    }

    const apiUsage: ApiUsage = {
      promptTokens: body.usage.prompt_tokens,
      completionTokens: body.usage.completion_tokens,
      totalTokens: body.usage.total_tokens
    }

    const apiResponse: ApiResponse = {
      id: body.id,
      choices: [apiChoice],
      usage: apiUsage
    }

    return apiResponse
  }

  async fetchModels(modelsUrl: string): Promise<string[]> {
    try {
      const httpRequest: http.HttpRequest = http.createHttp()
      const response: http.HttpResponse = await httpRequest.request(modelsUrl, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': 'Bearer ' + this.config.apiKey },
        connectTimeout: 10000,
        readTimeout: 10000
      })
      httpRequest.destroy()
      const raw: string = response.result as string
      const data: ModelsResponseData = JSON.parse(raw) as ModelsResponseData
      const names: string[] = []
      for (let i: number = 0; i < data.data.length && i < 20; i++) {
        const id: string = data.data[i].id || ''
        if (id.length > 0) {
          names.push(id)
        }
      }
      return names
    } catch (e) {
      Logger.warn('ApiClient', 'fetchModels failed: ' + (e as Error).message)
      return []
    }
  }
}
