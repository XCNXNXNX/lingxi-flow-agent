// McpClient - MCP (Model Context Protocol) client over Streamable HTTP transport
// Protocol: https://modelcontextprotocol.io/specification/2025-03-26
// Lifecycle: initialize -> notifications/initialized -> tools/list -> tools/call
// Remote tools are registered into ToolRegistry with 'mcp_' prefix to avoid collisions.
// Adapted from NanoClaw McpClient.ets (multi-server -> single server for Lingxi Flow)
import { http } from '@kit.NetworkKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'
import { configService } from './ConfigService'

const MCP_PROTOCOL_VERSION: string = '2025-03-26'
const TOOL_PREFIX: string = 'mcp_'

// --- Protocol types ---

interface McpRemoteTool {
  name: string
  description: string
  inputSchema: Record<string, Object>
}

interface McpJsonRpcResponse {
  jsonrpc: string
  id?: number
  result?: Record<string, Object>
  error?: McpJsonRpcError
}

interface McpJsonRpcError {
  code: number
  message: string
}

interface McpContentItem {
  type: string
  text: string
}

interface PostResult {
  body: string
  sessionId: string
}

interface McpClientInfo {
  name: string
  version: string
}

interface McpInitializeParams {
  protocolVersion: string
  capabilities: Record<string, Object>
  clientInfo: McpClientInfo
}

interface JsonRpcInitRequest {
  jsonrpc: string
  id: number
  method: string
  params: McpInitializeParams
}

interface JsonRpcNotification {
  jsonrpc: string
  method: string
}

interface JsonRpcSimpleRequest {
  jsonrpc: string
  id: number
  method: string
}

interface JsonRpcToolCallParams {
  name: string
  arguments: Record<string, Object>
}

interface JsonRpcToolCallRequest {
  jsonrpc: string
  id: number
  method: string
  params: JsonRpcToolCallParams
}

interface McpServerState {
  url: string
  sessionId: string
  tools: McpRemoteTool[]
  ready: boolean
}

export class McpClient {
  private state: McpServerState = { url: '', sessionId: '', tools: [], ready: false }
  private requestId: number = 0

  isReady(): boolean {
    return this.state.ready
  }

  getToolCount(): number {
    return this.state.tools.length
  }

  private nextId(): number {
    this.requestId++
    return this.requestId
  }

  // Connect to the configured MCP server and register remote tools into the registry.
  // Never throws - on failure the app continues with local tools only.
  async initAndRegister(registry: ToolRegistry): Promise<void> {
    const url: string = (await configService.getMcpUrl()).trim()
    if (url.length === 0) {
      Logger.info('McpClient', 'no MCP url configured, skip')
      return
    }
    const ok: boolean = await this.initServer(url)
    if (!ok) {
      return
    }
    for (let i: number = 0; i < this.state.tools.length; i++) {
      const tool: McpRemoteTool = this.state.tools[i]
      const registeredName: string = TOOL_PREFIX + tool.name
      if (registry.hasTool(registeredName)) {
        continue
      }
      const schema: Record<string, Object> = (tool.inputSchema as Record<string, Object>) ||
        JSON.parse('{"type":"object","properties":{}}') as Record<string, Object>
      const originalName: string = tool.name
      registry.registerTool(
        registeredName,
        (tool.description || 'MCP remote tool') + ' [MCP: ' + originalName + ']',
        schema,
        async (input: Record<string, Object>): Promise<string> => {
          return await this.callTool(originalName, input)
        }
      )
    }
    Logger.info('McpClient', 'registered ' + this.state.tools.length + ' remote tools')
  }

  // --- MCP lifecycle ---

  private async initServer(url: string): Promise<boolean> {
    this.state = { url: url, sessionId: '', tools: [], ready: false }
    try {
      Logger.info('McpClient', 'initializing server: ' + url)

      // 1) initialize
      const clientInfo: McpClientInfo = { name: 'lingxi-flow', version: '0.7.0' }
      const initParams: McpInitializeParams = {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: clientInfo
      }
      const initRequest: JsonRpcInitRequest = {
        jsonrpc: '2.0',
        id: this.nextId(),
        method: 'initialize',
        params: initParams
      }
      const initResult: PostResult = await this.postJsonRpc(url, '', JSON.stringify(initRequest))
      this.state.sessionId = initResult.sessionId
      const initResponse: McpJsonRpcResponse = this.parseJsonRpcResponse(initResult.body)
      if (initResponse.error) {
        throw new Error('initialize failed: ' + initResponse.error.message)
      }

      // 2) notifications/initialized
      const notification: JsonRpcNotification = {
        jsonrpc: '2.0',
        method: 'notifications/initialized'
      }
      await this.postJsonRpc(url, this.state.sessionId, JSON.stringify(notification))

      // 3) tools/list
      const toolsRequest: JsonRpcSimpleRequest = {
        jsonrpc: '2.0',
        id: this.nextId(),
        method: 'tools/list'
      }
      const toolsStr: string = (await this.postJsonRpc(url, this.state.sessionId, JSON.stringify(toolsRequest))).body
      const toolsResponse: McpJsonRpcResponse = this.parseJsonRpcResponse(toolsStr)
      if (toolsResponse.error) {
        throw new Error('tools/list failed: ' + toolsResponse.error.message)
      }
      if (toolsResponse.result) {
        const tools: McpRemoteTool[] = toolsResponse.result['tools'] as McpRemoteTool[]
        if (tools) {
          this.state.tools = tools
        }
      }

      this.state.ready = true
      Logger.info('McpClient', 'server ready, tools: ' + this.state.tools.length)
      return true
    } catch (e) {
      this.state.ready = false
      Logger.warn('McpClient', 'init failed: ' + (e as Error).message)
      return false
    }
  }

  async callTool(originalName: string, args: Record<string, Object>): Promise<string> {
    if (!this.state.ready) {
      return 'MCP 服务器不可用，请检查配置'
    }
    const params: JsonRpcToolCallParams = { name: originalName, arguments: args }
    const request: JsonRpcToolCallRequest = {
      jsonrpc: '2.0',
      id: this.nextId(),
      method: 'tools/call',
      params: params
    }
    const bodyStr: string = JSON.stringify(request)

    try {
      const body: string = (await this.postJsonRpc(this.state.url, this.state.sessionId, bodyStr)).body
      return this.extractCallResult(this.parseJsonRpcResponse(body))
    } catch (e) {
      // Session may have expired - re-init once and retry
      Logger.warn('McpClient', 'callTool failed, re-initializing: ' + (e as Error).message)
      const ok: boolean = await this.initServer(this.state.url)
      if (ok) {
        try {
          const body2: string = (await this.postJsonRpc(this.state.url, this.state.sessionId, bodyStr)).body
          return this.extractCallResult(this.parseJsonRpcResponse(body2))
        } catch (e2) {
          return 'MCP 调用失败: ' + (e2 as Error).message
        }
      }
      return 'MCP 调用失败: ' + (e as Error).message
    }
  }

  private extractCallResult(response: McpJsonRpcResponse): string {
    if (response.error) {
      return 'MCP 工具错误: ' + response.error.message
    }
    if (response.result) {
      const content: McpContentItem[] = response.result['content'] as McpContentItem[]
      if (content && content.length > 0) {
        const texts: string[] = []
        for (let i: number = 0; i < content.length; i++) {
          const item: McpContentItem = content[i]
          if (item.text) {
            texts.push(item.text)
          }
        }
        if (texts.length > 0) {
          return texts.join('\n')
        }
      }
      return JSON.stringify(response.result)
    }
    return 'MCP 工具无返回结果'
  }

  // --- HTTP layer ---

  private async postJsonRpc(url: string, sessionId: string, bodyStr: string): Promise<PostResult> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream'
    }
    if (sessionId.length > 0) {
      headers['Mcp-Session-Id'] = sessionId
    }

    const httpRequest: http.HttpRequest = http.createHttp()
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        readTimeout: 20000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      })

      const responseBody: string = (response.result || '') as string
      const responseHeaders: Record<string, string> = response.header as Record<string, string>
      let extractedSessionId: string = ''
      if (responseHeaders) {
        const keys: string[] = Object.keys(responseHeaders)
        for (let i: number = 0; i < keys.length; i++) {
          if (keys[i].toLowerCase() === 'mcp-session-id') {
            extractedSessionId = responseHeaders[keys[i]]
            break
          }
        }
      }

      httpRequest.destroy()
      const postResult: PostResult = { body: responseBody, sessionId: extractedSessionId }
      return postResult
    } catch (e) {
      httpRequest.destroy()
      throw e as Error
    }
  }

  // Parse JSON-RPC response; handles both plain JSON and SSE-wrapped responses
  private parseJsonRpcResponse(responseStr: string): McpJsonRpcResponse {
    let jsonStr: string = responseStr.trim()
    if (jsonStr.startsWith('data:') || jsonStr.startsWith('event:') || jsonStr.startsWith('id:')) {
      const lines: string[] = jsonStr.split('\n')
      for (let i: number = 0; i < lines.length; i++) {
        const line: string = lines[i]
        if (line.startsWith('data:')) {
          const dataContent: string = line.substring(5).trim()
          if (dataContent.length > 0 && dataContent !== '[DONE]') {
            jsonStr = dataContent
            break
          }
        }
      }
    }
    if (jsonStr.length === 0) {
      const empty: McpJsonRpcResponse = { jsonrpc: '2.0' }
      return empty
    }
    try {
      return JSON.parse(jsonStr) as McpJsonRpcResponse
    } catch (e) {
      Logger.error('McpClient', 'JSON parse failed: ' + jsonStr.substring(0, 200))
      const errResp: McpJsonRpcResponse = {
        jsonrpc: '2.0',
        error: { code: -1, message: 'JSON parse error' }
      }
      return errResp
    }
  }
}

export const mcpClient: McpClient = new McpClient()
