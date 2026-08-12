import { router, promptAction } from '@kit.ArkUI'
import { common, abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { agentCore } from '../engine/AgentCore'
import { configService } from '../services/ConfigService'
import { dbService } from '../engine/DatabaseService'
import { ApiClient } from '../services/ApiClient'
import { voiceService } from '../services/VoiceService'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { generateId } from '../utils/TextFormatter'
import { Logger } from '../utils/Logger'
import { AgentEvent, ApiConfig, ChatConversation, ToolCallRecord } from '../model/Types'
import { MarkdownText } from '../components/MarkdownText'

interface DisplayMessage {
  id: string
  content: string
  isFromMe: boolean
  timestamp: string
  toolCalls?: ToolCallRecord[]
  reasoning?: string
  isThinking?: boolean
  showTools?: boolean
  showReasoning?: boolean
  pairId?: string
}

const PAGE_SIZE: number = 15

@Entry
@Component
struct ChatPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State messages: DisplayMessage[] = []
  @State pagedMessages: DisplayMessage[] = []
  @State page: number = 1
  @State thinkSeconds: number = 0
  @State inputText: string = ''
  @State isRunning: boolean = false
  @State hasApiKey: boolean = false
  @State currentToolInfo: string = ''
  @State showSettings: boolean = false
  @State showConversations: boolean = false
  @State showChatMenu: boolean = false
  @State isRenaming: boolean = false
  @State renameText: string = ''
  @State conversations: ChatConversation[] = []
  @State chatName: string = '新对话'
  @State apiUrl: string = 'https://api.deepseek.com/v1'
  @State apiKey: string = ''
  @State apiModel: string = 'deepseek-chat'
  @State embedKey: string = ''
  @State mcpUrl: string = ''
  @State fetchingModels: boolean = false
  @State modelList: string[] = []
  @State deleteConfirmPair: string = ''
  @State sendScale: number = 1
  @State isListening: boolean = false
  @State speakingMsgId: string = ''
  private chatId: string = 'default'
  private scroller: Scroller = new Scroller()
  private typewriterTimer: number = -1
  private thinkTimer: number = -1
  private destroyed: boolean = false
  // Stream throttling: merge rapid stream/reasoning deltas into one UI update
  private uiThrottleTimer: number = -1
  private pendingThinkingId: string = ''
  private pendingContent: string = ''
  private pendingReasoning: string = ''

  async aboutToAppear(): Promise<void> {
    this.destroyed = false
    this.chatId = generateId()
    await this.refreshState()
    await this.loadConversations()
    // Consume insight intent preset (小艺唤起 → 自动执行)
    const preset: string | undefined = AppStorage.get<string>('intentPresetText')
    if (preset && preset.length > 0) {
      AppStorage.setOrCreate<string>('intentPresetText', '')
      this.inputText = preset
      setTimeout((): void => {
        if (!this.destroyed) {
          this.sendMessage()
        }
      }, 800)
    }
  }

  async onPageShow(): Promise<void> {
    await this.refreshState()
    await this.loadConversations()
  }

  aboutToDisappear(): void {
    this.destroyed = true
    this.savePosition()
    this.stopTypewriter()
    if (this.uiThrottleTimer >= 0) {
      clearTimeout(this.uiThrottleTimer)
      this.uiThrottleTimer = -1
    }
    if (this.thinkTimer >= 0) {
      clearInterval(this.thinkTimer)
      this.thinkTimer = -1
    }
    voiceService.cancelListening()
    voiceService.stopSpeaking()
    this.isListening = false
  }

  async refreshState(): Promise<void> {
    this.hasApiKey = await agentCore.hasApiKey()
    if (this.hasApiKey) {
      const cfg: ApiConfig = await configService.getApiConfig()
      this.apiUrl = cfg.baseUrl
      this.apiKey = cfg.apiKey
      this.apiModel = cfg.model
    }
    this.embedKey = await configService.getEmbeddingKey()
    this.mcpUrl = await configService.getMcpUrl()
  }

  async loadConversations(): Promise<void> {
    const all: ChatConversation[] = await dbService.getAllChats()
    // Hide internal task-run chats from the conversation list
    const filtered: ChatConversation[] = []
    for (let i: number = 0; i < all.length; i++) {
      if (!all[i].id.startsWith('task_')) {
        filtered.push(all[i])
      }
    }
    this.conversations = filtered
    if (this.conversations.length > 0 && this.conversations[0].id !== this.chatId) {
      const first: ChatConversation = this.conversations[0]
      this.chatId = first.id
      this.chatName = first.name
      await this.loadMessages()
    }
  }

  async switchChat(conv: ChatConversation): Promise<void> {
    // Save the previous chat's scroll position before switching
    await this.savePosition()
    this.chatId = conv.id
    this.chatName = conv.name
    this.showConversations = false
    await this.loadMessages()
  }

  async newChat(): Promise<void> {
    this.chatId = generateId()
    this.chatName = '新对话'
    this.messages = []
    this.syncPage()
    this.showConversations = false
    this.showChatMenu = false
  }

  async deleteChat(): Promise<void> {
    await dbService.deleteChat(this.chatId)
    this.showChatMenu = false
    this.messages = []
    this.syncPage()
    await this.loadConversations()
    if (this.conversations.length > 0) {
      this.chatId = this.conversations[0].id
      this.chatName = this.conversations[0].name
      await this.loadMessages()
    } else {
      await this.newChat()
    }
  }

  async startRename(): Promise<void> {
    this.renameText = this.chatName
    this.isRenaming = true
    this.showChatMenu = false
  }

  async doRename(): Promise<void> {
    const name: string = this.renameText.trim()
    if (name.length > 0) {
      this.chatName = name
      await dbService.renameChat(this.chatId, name)
      await this.loadConversations()
    }
    this.isRenaming = false
  }

  async deleteMessagePair(pairId: string): Promise<void> {
    const toRemove: string[] = []
    for (let i: number = 0; i < this.messages.length; i++) {
      if (this.messages[i].pairId === pairId) {
        toRemove.push(this.messages[i].id)
      }
    }
    for (let j: number = 0; j < toRemove.length; j++) {
      await dbService.deleteMessage(toRemove[j])
    }
    this.deleteConfirmPair = ''
    await this.loadMessages()
  }

  async loadMessages(): Promise<void> {
    // Restore pagination + scroll position of the previous chat (position memory)
    await this.savePosition()
    const savedY: string | null = await dbService.getKV('chat_scroll_' + this.chatId)
    const savedPage: string | null = await dbService.getKV('chat_page_' + this.chatId)

    const msgs = await dbService.getMessages(this.chatId, 1000)
    const displayMsgs: DisplayMessage[] = []
    let currentPairId: string = ''
    for (let i: number = 0; i < msgs.length; i++) {
      const m = msgs[i]
      if (m.isFromMe) {
        currentPairId = 'pair_' + m.id
      }
      displayMsgs.push({
        id: m.id,
        content: m.content,
        isFromMe: m.isFromMe,
        timestamp: m.timestamp,
        toolCalls: m.toolCalls,
        reasoning: m.reasoning,
        pairId: currentPairId
      })
    }
    this.messages = displayMsgs
    this.syncPage()

    // Restore page (clamped) then scroll to saved offset, else bottom
    const total: number = this.totalPages()
    const savedPageNum: number = savedPage ? parseInt(savedPage) : 1
    this.page = savedPageNum >= 1 && savedPageNum <= total ? savedPageNum : 1
    setTimeout((): void => {
      if (savedY && savedY.length > 0 && !this.destroyed) {
        const y: number = parseInt(savedY)
        if (y > 0) {
          this.scroller.scrollTo({ xOffset: 0, yOffset: y })
          return
        }
      }
      this.scrollToBottom()
    }, 200)
  }

  // Page window for the current page (latest messages are page 1)
  getPageMessages(): DisplayMessage[] {
    return this.pagedMessages
  }

  // Recompute the paged window from the full message array
  syncPage(): void {
    const total: number = this.messages.length
    const end: number = total - (this.page - 1) * PAGE_SIZE
    const start: number = Math.max(0, end - PAGE_SIZE)
    this.pagedMessages = this.messages.slice(start, Math.max(start, end))
  }

  totalPages(): number {
    return Math.max(1, Math.ceil(this.messages.length / PAGE_SIZE))
  }

  goPage(p: number): void {
    const total: number = this.totalPages()
    this.page = p < 1 ? 1 : (p > total ? total : p)
    this.syncPage()
    setTimeout((): void => {
      if (!this.destroyed && this.pagedMessages.length > 0) {
        this.scroller.scrollToIndex(0)
      }
    }, 80)
  }

  async savePosition(): Promise<void> {
    try {
      if (this.chatId.length === 0 || this.messages.length === 0) {
        return
      }
      const offset: number = this.scroller.currentOffset().yOffset
      await dbService.setKV('chat_scroll_' + this.chatId, String(Math.max(0, offset)))
      await dbService.setKV('chat_page_' + this.chatId, String(this.page))
    } catch (_e) {
      // ignore
    }
  }

  scrollToBottom(): void {
    setTimeout((): void => {
      if (!this.destroyed && this.getPageMessages().length > 0) {
        this.scroller.scrollToIndex(this.getPageMessages().length - 1)
      }
    }, 100)
  }

  async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim()
    if (!text || this.isRunning) { return }
    this.inputText = ''
    this.isRunning = true
    this.currentToolInfo = ''
    // Sending jumps back to the newest page
    this.page = 1
    this.syncPage()

    const pairId: string = 'pair_' + Date.now()
    const isFirstMsg: boolean = this.messages.length === 0

    const userMsg: DisplayMessage = {
      id: 'u' + Date.now(),
      content: text,
      isFromMe: true,
      timestamp: new Date().toISOString(),
      pairId: pairId
    }
    this.messages.push(userMsg)

    const thinkingId: string = 't' + Date.now()
    this.messages.push({
      id: thinkingId,
      content: '思考中...',
      isFromMe: false,
      timestamp: new Date().toISOString(),
      isThinking: true,
      pairId: pairId
    })
    this.syncPage()
    // Thinking stopwatch: shows elapsed seconds so waiting is visible
    this.thinkSeconds = 0
    if (this.thinkTimer >= 0) {
      clearInterval(this.thinkTimer)
    }
    this.thinkTimer = setInterval((): void => {
      if (!this.isRunning || this.destroyed) {
        clearInterval(this.thinkTimer)
        this.thinkTimer = -1
        return
      }
      this.thinkSeconds++
      const ti: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === thinkingId)
      if (ti >= 0) {
        const tm: DisplayMessage = this.messages[ti]
        // Only overwrite the placeholder while no content/reasoning arrived yet
        if (tm.isThinking && (tm.content === '思考中...' || tm.content.startsWith('思考中…'))) {
          this.messages[ti] = {
            id: tm.id, content: '思考中… ' + this.thinkSeconds + 's',
            isFromMe: tm.isFromMe, timestamp: tm.timestamp,
            toolCalls: tm.toolCalls, reasoning: tm.reasoning,
            isThinking: true, pairId: pairId
          }
          this.syncPage()
        }
      }
    }, 1000)
    this.scrollToBottom()

    if (!this.hasApiKey) {
      const reply: string = agentCore.getFallbackReply(text)
      this.startTypewriter(thinkingId, reply, pairId)
      return
    }

    const toolCalls: ToolCallRecord[] = []
    let streamedText: string = ''
    let reasoningText: string = ''
    let replyReceived: boolean = false
    try {
      await agentCore.runAgentStream(text, this.chatId, (event: AgentEvent): void => {
      if (event.type === 'reasoning') {
        // AI thinking: store it (shown collapsed on the final bubble), throttled UI update
        reasoningText = event.content
        this.updateThinkingBubble(thinkingId, streamedText, pairId, reasoningText)
      } else if (event.type === 'stream') {
        streamedText = event.content
        this.updateThinkingBubble(thinkingId, event.content, pairId)
      } else if (event.type === 'tool_use') {
        toolCalls.push({
          name: event.name, input: event.input,
          result: event.result, isError: event.isError
        })
        this.currentToolInfo = event.name
        const idx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === thinkingId)
        if (idx >= 0) {
          const ex: DisplayMessage = this.messages[idx]
          this.messages[idx] = {
            id: ex.id, content: event.name + '...',
            isFromMe: ex.isFromMe, timestamp: ex.timestamp,
            toolCalls: ex.toolCalls, reasoning: reasoningText,
            isThinking: ex.isThinking, pairId: pairId
          }
          this.syncPage()
        }
      } else if (event.type === 'text') {
        replyReceived = true
        if (streamedText.length > 0) {
          // Text was already streamed live - replace the bubble directly
          this.replaceThinking(thinkingId, event.content, pairId, toolCalls, reasoningText)
          this.isRunning = false
          this.currentToolInfo = ''
        } else {
          this.startTypewriter(thinkingId, event.content, pairId, toolCalls, reasoningText)
        }
      } else if (event.type === 'error') {
        replyReceived = true
        this.startTypewriter(thinkingId, '❌ ' + event.error, pairId)
      } else if (event.type === 'done') {
        // Safety net: always reset running state so the UI can never get stuck
        this.isRunning = false
        this.currentToolInfo = ''
        if (!replyReceived) {
          const stuckIdx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === thinkingId)
          if (stuckIdx >= 0) {
            const fallback: string = toolCalls.length > 0
              ? '✅ 已执行 ' + toolCalls.length + ' 个工具，但未返回文字回复，请继续提问'
              : '（未能获取到 AI 回复，请检查网络或 API 配置后重试）'
            this.replaceThinking(thinkingId, fallback, pairId, toolCalls, reasoningText)
          }
        }
        if (isFirstMsg) { this.generateChatName(text) }
      }
      this.scrollToBottom()
      })
    } catch (e) {
      // Safety net: never leave the chat stuck in running state
      this.isRunning = false
      this.currentToolInfo = ''
      this.startTypewriter(thinkingId, '❌ 出错了: ' + (e as Error).message, pairId)
    }

    await this.loadConversations()
  }

  replaceThinking(thinkingId: string, content: string, pairId: string, toolCalls?: ToolCallRecord[], reasoning?: string): void {
    const idx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === thinkingId)
    if (idx >= 0) {
      this.messages[idx] = {
        id: 'a' + Date.now(),
        content: content,
        isFromMe: false,
        timestamp: new Date().toISOString(),
        toolCalls: toolCalls && toolCalls.length > 0 ? toolCalls : undefined,
        reasoning: reasoning && reasoning.length > 0 ? reasoning : undefined,
        isThinking: false,
        pairId: pairId
      }
      this.syncPage()
    }
  }

  // Live-update the thinking bubble with streamed text - THROTTLED to ~12fps
  // so rapid SSE deltas (content + reasoning) don't trigger full re-renders per frame
  updateThinkingBubble(thinkingId: string, content: string, pairId: string, reasoning?: string): void {
    this.pendingThinkingId = thinkingId
    if (content.length > 0) {
      this.pendingContent = content
    }
    if (reasoning && reasoning.length > 0) {
      this.pendingReasoning = reasoning
    }
    if (this.uiThrottleTimer < 0) {
      this.uiThrottleTimer = setTimeout((): void => {
        this.uiThrottleTimer = -1
        const idx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === this.pendingThinkingId)
        if (idx >= 0) {
          const ex: DisplayMessage = this.messages[idx]
          // Live thinking visibility: show reasoning content while streaming it,
          // so the user sees progress instead of a frozen '思考中...'
          let liveContent: string = this.pendingContent.length > 0 ? this.pendingContent : ex.content
          if ((liveContent.length === 0 || liveContent.startsWith('思考中')) && this.pendingReasoning.length > 0) {
            liveContent = '💭 ' + (this.pendingReasoning.length > 150
              ? this.pendingReasoning.substring(0, 150) + '…'
              : this.pendingReasoning)
          }
          this.messages[idx] = {
            id: ex.id,
            content: liveContent,
            isFromMe: false,
            timestamp: ex.timestamp,
            toolCalls: ex.toolCalls,
            reasoning: this.pendingReasoning.length > 0 ? this.pendingReasoning : ex.reasoning,
            isThinking: true,
            pairId: pairId
          }
          this.syncPage()
        }
      }, 80)
    }
  }

  startTypewriter(thinkingId: string, fullText: string, pairId: string, toolCalls?: ToolCallRecord[], reasoning?: string): void {
    this.stopTypewriter()
    if (this.thinkTimer >= 0) {
      clearInterval(this.thinkTimer)
      this.thinkTimer = -1
    }
    const idx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === thinkingId)
    if (idx < 0) { return }
    const base: DisplayMessage = this.messages[idx]
    const finalReasoning: string | undefined = reasoning && reasoning.length > 0 ? reasoning : base.reasoning
    let pos: number = 0
    const speed: number = fullText.length > 200 ? 10 : 15

    this.typewriterTimer = setInterval(() => {
      pos++
      if (pos >= fullText.length) {
        this.messages[idx] = {
          id: 'a' + Date.now(),
          content: fullText,
          isFromMe: false,
          timestamp: new Date().toISOString(),
          toolCalls: toolCalls && toolCalls.length > 0 ? toolCalls : undefined,
          reasoning: finalReasoning,
          isThinking: false,
          pairId: pairId
        }
        clearInterval(this.typewriterTimer)
        this.typewriterTimer = -1
        this.isRunning = false
        this.currentToolInfo = ''
        this.scrollToBottom()
      } else {
        this.messages[idx] = {
          id: base.id,
          content: fullText.substring(0, pos),
          isFromMe: base.isFromMe,
          timestamp: base.timestamp,
          toolCalls: toolCalls && toolCalls.length > 0 ? toolCalls : undefined,
          reasoning: finalReasoning,
          isThinking: true,
          pairId: pairId
        }
      }
      this.syncPage()
      this.scrollToBottom()
    }, speed)
  }

  stopTypewriter(): void {
    if (this.typewriterTimer >= 0) {
      clearInterval(this.typewriterTimer)
      this.typewriterTimer = -1
    }
  }

  async generateChatName(firstMsg: string): Promise<void> {
    const short: string = firstMsg.length > 10 ? firstMsg.substring(0, 10) : firstMsg
    this.chatName = short.replace(/\n/g, ' ').trim()
    await dbService.ensureChat(this.chatId, this.chatName)
    await this.loadConversations()
  }

  async saveConfig(): Promise<void> {
    const cfg: ApiConfig = {
      apiKey: this.apiKey, baseUrl: this.apiUrl, model: this.apiModel,
      maxTokens: 8192, temperature: 0.7
    }
    await configService.saveApiConfig(cfg)
    await configService.saveEmbeddingKey(this.embedKey.trim())
    await configService.saveMcpUrl(this.mcpUrl.trim())
    this.hasApiKey = true
    this.showSettings = false
  }

  async fetchModels(): Promise<void> {
    this.fetchingModels = true
    try {
      const cfg: ApiConfig = await configService.getApiConfig()
      cfg.apiKey = this.apiKey
      const client: ApiClient = new ApiClient(cfg)
      const modelsUrl: string = this.apiUrl.replace(/\/v1\/?$/, '') + '/v1/models'
      this.modelList = await client.fetchModels(modelsUrl)
      if (this.modelList.length === 0) {
        this.modelList = ['deepseek-chat', 'deepseek-reasoner']
      }
    } catch (e) { this.modelList = ['deepseek-chat', 'deepseek-reasoner'] }
    this.fetchingModels = false
  }

  async toggleVoiceInput(): Promise<void> {
    if (this.isListening) {
      await voiceService.stopListening()
      this.isListening = false
      return
    }
    const granted: boolean = await this.requestMicPermission()
    if (!granted) {
      return
    }
    this.isListening = true
    await voiceService.startListening(
      (text: string): void => { this.inputText = text },
      (text: string): void => {
        this.inputText = text
        this.isListening = false
      },
      (msg: string): void => {
        this.isListening = false
        promptAction.showToast({ message: msg, duration: 2500 })
      }
    )
    if (!voiceService.getListening()) {
      this.isListening = false
    }
  }

  async requestMicPermission(): Promise<boolean> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const res: PermissionRequestResult = await atManager.requestPermissionsFromUser(
        context, ['ohos.permission.MICROPHONE'] as Permissions[])
      if (res.authResults && res.authResults.length > 0) {
        return res.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      }
      return false
    } catch (e) {
      return false
    }
  }

  private shorten(text: string, maxLen: number): string {
    if (text.length <= maxLen) {
      return text
    }
    return text.substring(0, maxLen) + '…'
  }

  toggleSpeak(msg: DisplayMessage): void {
    if (this.speakingMsgId === msg.id) {
      voiceService.stopSpeaking()
      this.speakingMsgId = ''
      return
    }
    voiceService.stopSpeaking()
    this.speakingMsgId = msg.id
    voiceService.speak(msg.content, (): void => {
      this.speakingMsgId = ''
    })
  }

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  build() {
    Stack() {
      Column() {
        // Header
        Row() {
          Image($r('sys.symbol.arrow_left'))
            .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
            .fillColor(this.col().textPrimary)
            .onClick(() => { router.back() })

          if (this.isRenaming) {
            TextInput({ text: this.renameText })
              .layoutWeight(1).height(36)
              .fontColor(this.col().textPrimary)
              .backgroundColor(this.col().surfaceVariant)
              .borderRadius($r('app.float.radius_sm'))
              .padding({ left: 12, right: 12 })
              .onChange((v: string): void => { this.renameText = v })
              .onSubmit(() => { this.doRename() })
            Button('✓')
              .fontSize(14).fontColor(this.col().accent)
              .onClick(() => { this.doRename() })
          } else {
            Text(this.chatName)
              .fontSize($r('app.float.font_size_subtitle'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1).textAlign(TextAlign.Center)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => { this.startRename() })
          }

          Button('▼')
            .fontSize(12).fontColor(this.col().textSecondary)
            .width(30).height(30)
            .backgroundColor(this.col().surfaceVariant).borderRadius(15)
            .margin({ left: 4, right: 6 })
            .onClick(() => { this.showChatMenu = !this.showChatMenu })

          Button('API')
            .fontSize($r('app.float.font_size_caption'))
            .fontColor(this.hasApiKey ? '#047857' : '#92400E')
            .backgroundColor(this.col().surfaceVariant)
            .borderRadius($r('app.float.radius_sm'))
            .padding({ left: $r('app.float.spacing_sm'), right: $r('app.float.spacing_sm') })
            .onClick(() => { this.showSettings = !this.showSettings })
        }
        .width('100%')
        .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_sm'),
          top: $r('app.float.spacing_sm'), bottom: $r('app.float.spacing_sm') })
        .backgroundColor(this.col().glassNav).backdropBlur(10)

        // Chat menu popup
        if (this.showChatMenu) {
          Column() {
            this.menuBtn('＋ 新对话', () => { this.newChat() }, this.col())
            this.menuBtn('☰ 对话列表', () => { this.showConversations = true; this.showChatMenu = false }, this.col())
            this.menuBtn('✎ 重命名', () => { this.startRename() }, this.col())
            this.menuBtn('✕ 删除', () => { this.deleteChat() }, this.col(), '#DC2626')
          }
          .width(120)
          .padding($r('app.float.spacing_sm'))
          .backgroundColor(this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .border({ width: 1, color: this.col().divider })
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: 4 })
          .position({ x: '46%', y: 48 })
          .zIndex(100)
        }

        // Messages
        List({ scroller: this.scroller }) {
          ForEach(this.getPageMessages(), (msg: DisplayMessage): void => {
            ListItem() {
              Column() {
                // Tool calls (collapsed by default)
                if (msg.toolCalls && msg.toolCalls.length > 0) {
                  Row() {
                    Text(msg.showTools ? '▾' : '▸')
                      .fontSize(10).fontColor(this.col().textTertiary)
                      .margin({ right: 4 })
                    Text('🔧 ' + msg.toolCalls.length + ' 个工具调用')
                      .fontSize(11).fontColor(this.col().textTertiary)
                  }
                  .width('100%').padding({ left: 4, right: 4, top: 2 })
                  .onClick(() => {
                    const tIdx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === msg.id)
                    if (tIdx >= 0) {
                      const tm: DisplayMessage = this.messages[tIdx]
                      this.messages[tIdx] = {
                        id: tm.id, content: tm.content, isFromMe: tm.isFromMe, timestamp: tm.timestamp,
                        toolCalls: tm.toolCalls, reasoning: tm.reasoning,
                        isThinking: tm.isThinking, showTools: !tm.showTools,
                        showReasoning: tm.showReasoning, pairId: tm.pairId
                      }
                      this.syncPage()
                    }
                  })
                  if (msg.showTools) {
                    Column() {
                      ForEach(msg.toolCalls, (tc: ToolCallRecord): void => {
                        Column() {
                          Row() {
                            Text((tc.isError ? '✗ ' : '◎ ') + tc.name)
                              .fontSize(11)
                              .fontColor(tc.isError ? '#DC2626' : this.col().textSecondary)
                              .fontWeight(FontWeight.Medium)
                            Blank()
                            Text(tc.isError ? '失败' : '成功')
                              .fontSize(9).fontColor(tc.isError ? '#DC2626' : '#047857')
                          }
                          .width('100%')
                          if (tc.input && tc.input.length > 0) {
                            Text('参数: ' + this.shorten(tc.input, 120))
                              .fontSize(10).fontColor(this.col().textTertiary).width('100%')
                              .margin({ top: 2 })
                          }
                          if (tc.result && tc.result.length > 0) {
                            Text('结果: ' + this.shorten(tc.result, 200))
                              .fontSize(10).fontColor(this.col().textTertiary).width('100%')
                              .margin({ top: 2 })
                          }
                        }
                        .width('100%')
                        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                        .backgroundColor(this.col().surfaceVariant)
                        .borderRadius($r('app.float.radius_sm'))
                        .margin({ top: 4 })
                      })
                    }
                    .width('100%').padding({ left: 4, right: 4, top: 2 })
                  }
                }

                Row() {
                  if (msg.isFromMe) { Blank() }

                  Column() {
                    MarkdownText({
                      content: msg.content,
                      textColor: msg.isFromMe ? '#FFFFFF' : this.col().textPrimary,
                      accentColor: msg.isFromMe ? 'rgba(255,255,255,0.7)' : this.col().accent
                    })

                    // AI-generated content explicit label (compliance: 人工智能生成合成内容标识)
                    if (!msg.isFromMe && !msg.isThinking && msg.content.length > 0) {
                      Text('✨ AI 生成')
                        .fontSize(9)
                        .fontColor(this.col().textTertiary)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor('rgba(127,127,127,0.1)')
                        .borderRadius($r('app.float.radius_sm'))
                        .margin({ top: 6 })
                    }

                    // Thinking (reasoning) - collapsed by default, tap to expand
                    if (!msg.isFromMe && !msg.isThinking && msg.reasoning && msg.reasoning.length > 0) {
                      Row() {
                        Text(msg.showReasoning ? '▾' : '▸')
                          .fontSize(10).fontColor(this.col().accent).margin({ right: 4 })
                        Text(msg.showReasoning ? '收起思考' : '💭 思考过程')
                          .fontSize(10).fontColor(this.col().accent)
                      }
                      .margin({ top: 6 })
                      .onClick(() => {
                        const rIdx: number = this.messages.findIndex((m: DisplayMessage): boolean => m.id === msg.id)
                        if (rIdx >= 0) {
                          const rm: DisplayMessage = this.messages[rIdx]
                          this.messages[rIdx] = {
                            id: rm.id, content: rm.content, isFromMe: rm.isFromMe, timestamp: rm.timestamp,
                            toolCalls: rm.toolCalls, reasoning: rm.reasoning,
                            isThinking: rm.isThinking, showTools: rm.showTools,
                            showReasoning: !rm.showReasoning, pairId: rm.pairId
                          }
                          this.syncPage()
                        }
                      })
                      if (msg.showReasoning) {
                        Text(msg.reasoning)
                          .fontSize(10)
                          .fontColor(this.col().textTertiary)
                          .fontStyle(FontStyle.Italic)
                          .width('100%')
                          .padding({ left: 6, right: 6, top: 6, bottom: 4 })
                          .backgroundColor('rgba(127,127,127,0.08)')
                          .borderRadius($r('app.float.radius_sm'))
                          .margin({ top: 4 })
                      }
                    }

                    // TTS speak button (AI messages only)
                    if (!msg.isFromMe && !msg.isThinking && msg.content.length > 0) {
                      Text(this.speakingMsgId === msg.id ? '🔇' : '🔊')
                        .fontSize(12)
                        .fontColor(this.speakingMsgId === msg.id ? this.col().accent : this.col().textTertiary)
                        .padding({ top: 2 })
                        .onClick(() => { this.toggleSpeak(msg) })
                    }

                    // Delete pair button (only on user messages with a pair)
                    if (msg.isFromMe && !msg.isThinking && msg.pairId) {
                      Row() {
                        if (this.deleteConfirmPair === msg.pairId) {
                          Text('确认删除本轮?')
                            .fontSize(10).fontColor('#DC2626')
                            .margin({ right: 4 })
                            .onClick(() => { this.deleteMessagePair(msg.pairId!) })
                          Text('取消')
                            .fontSize(10).fontColor(this.col().textTertiary)
                            .onClick(() => { this.deleteConfirmPair = '' })
                        } else {
                          Text('删除')
                            .fontSize(10).fontColor(this.col().textTertiary)
                            .onClick(() => { this.deleteConfirmPair = msg.pairId! })
                        }
                      }
                      .margin({ top: 4 })
                    }
                  }
                  .constraintSize({ maxWidth: '75%' })
                  .backgroundColor(msg.isFromMe ? this.col().accent :
                    (msg.isThinking ? this.col().surfaceVariant : this.col().surface))
                  .borderRadius($r('app.float.radius_surface'))
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  .alignItems(msg.isFromMe ? HorizontalAlign.End : HorizontalAlign.Start)

                  if (!msg.isFromMe) { Blank() }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 4, bottom: 4 })
              }
            }
          })
        }
        .width('100%').layoutWeight(1)
        .backgroundColor(this.col().bg)

        // Tool status
        if (this.currentToolInfo) {
          Row() {
            LoadingProgress().width(12).height(12).color(this.col().accent).margin({ right: 8 })
            Text(this.currentToolInfo)
              .fontSize(12).fontColor(this.col().textSecondary).fontStyle(FontStyle.Italic)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.col().surfaceVariant)
        }

        // Pagination bar (page-by-page browsing, same conversation = AI memory kept)
        if (this.messages.length > PAGE_SIZE) {
          Row() {
            Text('‹')
              .fontSize(16).fontColor(this.page > 1 ? this.col().textPrimary : this.col().textTertiary)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => { this.goPage(this.page - 1) })
            Text('第 ' + this.page + '/' + this.totalPages() + ' 页')
              .fontSize(11).fontColor(this.col().textTertiary)
            Text('›')
              .fontSize(16).fontColor(this.page < this.totalPages() ? this.col().textPrimary : this.col().textTertiary)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => { this.goPage(this.page + 1) })
            if (this.page > 1) {
              Text('最新')
                .fontSize(11).fontColor(this.col().accent)
                .padding({ left: 8, right: 4, top: 6, bottom: 6 })
                .onClick(() => { this.goPage(1) })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(this.col().glassNav)
        }

        // Input
        Row() {
          Button({ type: ButtonType.Circle }) {
            Image(this.isListening ? $r('app.media.voice_2') : $r('app.media.voice_1'))
              .width(24).height(24)
          }
          .width(44).height(44)
          .backgroundColor(this.isListening ? '#DC2626' : this.col().surfaceVariant)
          .margin({ right: 8 })
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => { this.toggleVoiceInput() })

          TextInput({ text: this.inputText, placeholder: this.isListening ? '聆听中... 点击结束' : '输入消息...' })
            .layoutWeight(1).height(44)
            .borderRadius($r('app.float.radius_surface'))
            .backgroundColor(this.col().surfaceVariant)
            .fontColor(this.col().textPrimary)
            .placeholderColor(this.col().textTertiary)
            .padding({ left: 16, right: 16 })
            .onChange((v: string): void => { this.inputText = v })
            .onSubmit((): void => { this.sendMessage() })

          Button({ type: ButtonType.Circle }) {
            Text('↑').fontSize(18).fontColor('#FFFFFF')
          }
          .width(44).height(44)
          .backgroundColor(this.isRunning ? this.col().textTertiary : this.col().accent)
          .margin({ left: 8 })
          .scale({ x: this.sendScale, y: this.sendScale })
          .enabled(!this.isRunning)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => {
            this.sendScale = 0.85
            setTimeout(() => { if (!this.destroyed) { this.sendScale = 1 } }, 150)
            this.sendMessage()
          })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.col().surface)
        .border({ width: { top: 1 }, color: this.col().divider })
      }
      .width('100%').height('100%')

      // Conversations list overlay
      if (this.showConversations) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .onClick(() => { this.showConversations = false })

        Column() {
          Row() {
            Text('对话列表')
              .fontSize($r('app.float.font_size_subtitle'))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.col().textPrimary).layoutWeight(1)
            Text('✕').fontSize(20).fontColor(this.col().textSecondary)
              .onClick(() => { this.showConversations = false })
          }
          .width('100%').padding($r('app.float.spacing_md'))

          Divider().color(this.col().divider)

          if (this.conversations.length === 0) {
            Text('暂无对话')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textTertiary)
              .margin({ top: $r('app.float.spacing_xxl') })
              .width('100%').textAlign(TextAlign.Center)
          }

          List() {
            ForEach(this.conversations, (conv: ChatConversation): void => {
              ListItem() {
                Row() {
                  Column() {
                    Text(conv.name)
                      .fontSize($r('app.float.font_size_body'))
                      .fontColor(conv.id === this.chatId ? this.col().accent : this.col().textPrimary)
                      .fontWeight(conv.id === this.chatId ? FontWeight.Bold : FontWeight.Normal)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (conv.lastMessagePreview && conv.lastMessagePreview.length > 0) {
                      Text(conv.lastMessagePreview)
                        .fontSize($r('app.float.font_size_small'))
                        .fontColor(this.col().textTertiary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)

                  Text('›').fontSize(18).fontColor(this.col().textTertiary)
                }
                .width('100%').padding($r('app.float.spacing_md'))
                .backgroundColor(conv.id === this.chatId ? this.col().surfaceVariant : 'transparent')
                .borderRadius($r('app.float.radius_md'))
                .onClick(() => { this.switchChat(conv) })
              }
            })
          }
          .width('100%').layoutWeight(1)
        }
        .width('90%').height('80%')
        .backgroundColor(this.col().surface)
        .borderRadius($r('app.float.radius_lg'))
        .border({ width: 1, color: this.col().divider })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 8 })
        .animation({ duration: 300, curve: Curve.EaseOut })
      }

      // Settings overlay
      if (this.showSettings) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .onClick(() => { this.showSettings = false })

        Scroll() {
          Column() {
            Row() {
              Text('API 配置')
                .fontSize($r('app.float.font_size_subtitle'))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.col().textPrimary)
              Blank()
              Text('完整设置 ›')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().accent)
                .onClick(() => {
                  this.showSettings = false
                  router.pushUrl({ url: 'pages/ApiSettingsPage' })
                })
            }
            .width('100%').margin({ bottom: $r('app.float.spacing_md') })

            this.settingsField('API 地址', this.col())
            TextInput({ text: this.apiUrl, placeholder: 'https://api.deepseek.com/v1' })
              .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
              .onChange((v: string): void => { this.apiUrl = v })
              .margin({ top: $r('app.float.spacing_xs'), bottom: $r('app.float.spacing_md') })

            this.settingsField('API Key', this.col())
            TextInput({ text: this.apiKey, placeholder: 'sk-...' })
              .type(InputType.Password)
              .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
              .onChange((v: string): void => { this.apiKey = v })
              .margin({ top: $r('app.float.spacing_xs'), bottom: $r('app.float.spacing_md') })

            this.settingsField('嵌入 Key（可选，RAG 知识库）', this.col())
            TextInput({ text: this.embedKey, placeholder: 'sk-...（SiliconFlow，留空则用关键词检索）' })
              .type(InputType.Password)
              .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
              .onChange((v: string): void => { this.embedKey = v })
              .margin({ top: $r('app.float.spacing_xs'), bottom: $r('app.float.spacing_md') })

            this.settingsField('MCP 服务器', this.col())
            Row() {
              Text('MCP 配置已移至 API 设置页')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .layoutWeight(1)
              Text('去配置 ›')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().accent)
                .onClick(() => {
                  this.showSettings = false
                  router.pushUrl({ url: 'pages/ApiSettingsPage' })
                })
            }
            .width('100%').margin({ top: $r('app.float.spacing_xs'), bottom: $r('app.float.spacing_md') })

            this.settingsField('模型', this.col())
            TextInput({ text: this.apiModel, placeholder: 'deepseek-chat' })
              .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
              .onChange((v: string): void => { this.apiModel = v })
              .margin({ top: $r('app.float.spacing_xs'), bottom: $r('app.float.spacing_sm') })

            Button('获取模型')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textPrimary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
              .onClick(() => { this.fetchModels() })
              .margin({ bottom: $r('app.float.spacing_sm') })

            if (this.fetchingModels) { LoadingProgress().width(20).height(20).color(this.col().accent) }
            if (this.modelList.length > 0) {
              ForEach(this.modelList, (m: string): void => {
                Text(m)
                  .fontSize($r('app.float.font_size_small'))
                  .fontColor(m === this.apiModel ? this.col().accent : this.col().textSecondary)
                  .onClick(() => { this.apiModel = m }).padding({ top: 4, bottom: 4 })
              })
            }

            Button('保存')
              .fontSize($r('app.float.font_size_body'))
              .backgroundColor(this.col().accent).fontColor('#FFFFFF')
              .borderRadius($r('app.float.radius_md'))
              .width('100%').height(44)
              .margin({ top: $r('app.float.spacing_md') })
              .onClick(() => { this.saveConfig() })
          }
          .width('100%').padding($r('app.float.spacing_md'))
        }
        .width('100%').height('55%')
        .backgroundColor(this.col().surface)
        .borderRadius($r('app.float.radius_lg'))
        .border({ width: 1, color: this.col().divider })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 8 })
        .animation({ duration: 300, curve: Curve.EaseOut })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  menuBtn(label: string, onClick: () => void, colors: ThemeColors, color?: string) {
    Text(label)
      .fontSize($r('app.float.font_size_small'))
      .fontColor(color || colors.textPrimary)
      .width('100%').padding({ top: 8, bottom: 8, left: 8 })
      .borderRadius($r('app.float.radius_sm'))
      .onClick(onClick)
  }

  @Builder
  settingsField(label: string, colors: ThemeColors) {
    Text(label)
      .fontSize($r('app.float.font_size_caption'))
      .fontColor(colors.textSecondary)
  }
}
