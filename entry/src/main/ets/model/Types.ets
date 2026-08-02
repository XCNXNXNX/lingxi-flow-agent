// Types for Lingxi Flow - Unified type definitions
// Ported from NanoClaw types.ts + DeepSeek API types

// --- Chat & Messages ---

export interface ChatMessage {
  id: string
  chatId: string
  sender: string
  senderName: string
  content: string
  timestamp: string
  isFromMe: boolean
  toolCalls?: ToolCallRecord[]
}

export interface ChatConversation {
  id: string
  name: string
  lastMessageTime: string
  lastMessagePreview: string
}

// --- Agent Tool Use ---

export interface ToolDefinition {
  type: 'function'
  function: ToolFunction
}

export interface ToolFunction {
  name: string
  description: string
  parameters: Record<string, Object>
}

export interface ToolCall {
  id: string
  type: 'function'
  function: ToolCallFunction
}

export interface ToolCallFunction {
  name: string
  arguments: string
}

export interface ToolResult {
  toolCallId: string
  content: string
  isError: boolean
}

export interface ToolCallRecord {
  name: string
  input: string
  result: string
  isError: boolean
}

// --- DeepSeek API (OpenAI-compatible) ---

export interface ApiConfig {
  apiKey: string
  baseUrl: string
  model: string
  maxTokens: number
  temperature: number
}

export interface ApiMessage {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content?: string | null
  toolCalls?: ToolCall[]
  toolCallId?: string
}

export interface ApiResponse {
  id: string
  choices: ApiChoice[]
  usage: ApiUsage
}

export interface ApiChoice {
  index: number
  message: ApiMessage
  finishReason: string
}

export interface ApiUsage {
  promptTokens: number
  completionTokens: number
  totalTokens: number
}

// --- Scheduled Tasks ---

export interface ScheduledTask {
  id: string
  chatId: string
  prompt: string
  scheduleType: 'cron' | 'interval' | 'once'
  scheduleValue: string
  nextRun: string | null
  lastRun: string | null
  lastResult: string | null
  status: 'active' | 'paused' | 'completed'
  createdAt: string
}

export interface TaskRunLog {
  taskId: string
  runAt: string
  durationMs: number
  status: 'success' | 'error'
  result: string | null
  error: string | null
}

// --- Workflow runs (ResultPage checkpoint/resume) ---

export interface WorkflowRun {
  id: string
  goal: string
  status: 'running' | 'done' | 'error'
  stepsJson: string
  result: string
  chatId: string
  createdAt: string
  updatedAt: string
}

// --- Agent Events (for UI streaming) ---

export interface AgentTextEvent {
  type: 'text'
  content: string
}

export interface AgentStreamEvent {
  type: 'stream'
  content: string
}

export interface AgentToolUseEvent {
  type: 'tool_use'
  name: string
  input: string
  result: string
  isError: boolean
}

export interface AgentErrorEvent {
  type: 'error'
  error: string
}

export interface AgentDoneEvent {
  type: 'done'
}

export type AgentEvent = AgentTextEvent | AgentStreamEvent | AgentToolUseEvent | AgentErrorEvent | AgentDoneEvent

// --- Task Steps (for WorkflowEngine / ResultPage) ---

export enum TaskStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  SKIPPED = 'skipped'
}

export class TaskStep {
  id: string
  name: string
  status: TaskStatus
  deviceName: string
  pluginName: string
  result: string
  extra: string
  scheduledTime: number
  notifyEnabled: boolean
  notifyMessage: string

  constructor(id: string, name: string, status: TaskStatus = TaskStatus.PENDING) {
    this.id = id
    this.name = name
    this.status = status
    this.deviceName = ''
    this.pluginName = ''
    this.result = ''
    this.extra = ''
    this.scheduledTime = 0
    this.notifyEnabled = false
    this.notifyMessage = ''
  }
}

// --- Device Types ---

export enum DeviceType {
  PHONE = 'phone',
  TABLET = 'tablet',
  WATCH = 'watch',
  TV = 'tv',
  CAR = 'car',
  UNKNOWN = 'unknown'
}

export enum DeviceConnectionStatus {
  CONNECTED = 'connected',
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  UNAVAILABLE = 'unavailable'
}

export class DeviceInfo {
  deviceId: string
  deviceName: string
  deviceType: DeviceType
  status: DeviceConnectionStatus
  batteryLevel: number
  ipAddress?: string
  osVersion?: string

  constructor(id: string, name: string, type: DeviceType = DeviceType.UNKNOWN) {
    this.deviceId = id
    this.deviceName = name
    this.deviceType = type
    this.status = DeviceConnectionStatus.DISCONNECTED
    this.batteryLevel = 100
  }

  getStatusText(): string {
    switch (this.status) {
      case DeviceConnectionStatus.CONNECTED:
        return '已连接'
      case DeviceConnectionStatus.CONNECTING:
        return '连接中'
      case DeviceConnectionStatus.DISCONNECTED:
        return '未连接'
      case DeviceConnectionStatus.UNAVAILABLE:
        return '不可用'
      default:
        return '未知'
    }
  }

  getTypeText(): string {
    switch (this.deviceType) {
      case DeviceType.PHONE:
        return '手机'
      case DeviceType.TABLET:
        return '平板'
      case DeviceType.WATCH:
        return '手表'
      case DeviceType.TV:
        return '电视'
      case DeviceType.CAR:
        return '车机'
      default:
        return '未知设备'
    }
  }
}

// --- Routing ---

export class PageParams {
  presetText?: string
  steps?: TaskStep[]
  intentName?: string
}

// --- LLM Provider ---

export class LLMProvider {
  name: string
  baseUrl: string
  modelsUrl: string
  chatPath: string
  defaultModel: string
  description: string

  constructor(
    name: string,
    baseUrl: string,
    modelsUrl: string,
    description: string,
    chatPath: string = '/v1/chat/completions',
    defaultModel: string = ''
  ) {
    this.name = name
    this.baseUrl = baseUrl
    this.modelsUrl = modelsUrl
    this.chatPath = chatPath
    this.defaultModel = defaultModel
    this.description = description
  }
}
