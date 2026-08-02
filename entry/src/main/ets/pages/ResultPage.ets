// ResultPage - AI-powered task workflow system
import { router } from '@kit.ArkUI'
import { agentCore } from '../engine/AgentCore'
import { configService } from '../services/ConfigService'
import { dbService } from '../engine/DatabaseService'
import { distributedService, TaskStatePayload } from '../services/DistributedService'
import { generateId } from '../utils/TextFormatter'
import {
  AgentEvent,
  AgentTextEvent,
  AgentToolUseEvent,
  AgentErrorEvent,
  TaskStatus,
  WorkflowRun
} from '../model/Types'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { MarkdownText } from '../components/MarkdownText'

interface AiStep {
  id: string
  name: string
  status: TaskStatus
  result: string
}

@Entry
@Component
struct ResultPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State steps: AiStep[] = []
  @State goal: string = ''
  @State inputText: string = ''
  @State progress: number = 0
  @State flowStatus: string = 'idle'
  @State allDone: boolean = false
  @State elapsed: number = 0
  @State aiResponse: string = ''
  @State hasApiKey: boolean = false
  @State typedResponse: string = ''
  @State lastRun: WorkflowRun | null = null
  @State showLastRun: boolean = false
  private startTime: number = 0
  private timer: number = -1
  private executing: boolean = false
  private twTimer: number = -1
  private currentRunId: string = ''
  private currentChatId: string = ''
  private runCreatedAt: string = ''
  private resumeChatId: string = ''

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  async aboutToAppear(): Promise<void> {
    this.hasApiKey = await configService.hasApiKey()
    await this.loadLastRun()
  }

  async loadLastRun(): Promise<void> {
    try {
      const run: WorkflowRun | null = await dbService.getLatestWorkflowRun()
      if (run && run.goal.length > 0 && this.goal !== run.goal) {
        this.lastRun = run
        this.showLastRun = true
      } else {
        this.lastRun = null
        this.showLastRun = false
      }
    } catch (_e) {
      this.lastRun = null
    }
  }

  // Resume the last task with its full conversation context
  resumeLastRun(): void {
    if (!this.lastRun) {
      return
    }
    this.goal = this.lastRun.goal
    this.inputText = this.lastRun.goal
    this.resumeChatId = this.lastRun.chatId
    this.showLastRun = false
    try {
      const steps: AiStep[] = JSON.parse(this.lastRun.stepsJson) as AiStep[]
      this.steps = steps
    } catch (_e) {
      this.steps = []
    }
    this.startAiFlow()
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1 }
    if (this.twTimer >= 0) { clearInterval(this.twTimer); this.twTimer = -1 }
  }

  async startAiFlow(): Promise<void> {
    const text: string = this.inputText.trim()
    if (!text || this.executing) { return }

    this.executing = true
    this.allDone = false
    this.goal = text
    this.aiResponse = ''
    this.typedResponse = ''
    if (this.resumeChatId.length === 0) {
      // fresh run: reset everything
      this.steps = []
    }
    this.progress = 0
    this.inputText = ''
    this.startTime = Date.now()
    this.flowStatus = 'running'
    this.lastRun = null
    this.showLastRun = false

    this.timer = setInterval(() => {
      this.elapsed = Date.now() - this.startTime
    }, 100)

    let chatId: string = this.resumeChatId
    if (chatId.length === 0) {
      chatId = 'task_' + generateId()
    }
    this.resumeChatId = ''
    this.currentChatId = chatId
    this.currentRunId = 'wf_' + generateId()
    this.runCreatedAt = new Date().toISOString()

    await agentCore.runAgent(text, chatId, (event: AgentEvent): void => {
      if (event.type === 'tool_use') {
        const te: AgentToolUseEvent = event as AgentToolUseEvent
        this.steps.push({
          id: 's' + Date.now() + '_' + this.steps.length,
          name: te.name,
          status: te.isError ? TaskStatus.FAILED : TaskStatus.COMPLETED,
          result: te.result
        })
        this.progress = Math.round(Math.min(this.steps.length / 8, 1) * 100)
        this.saveRun('running', JSON.stringify(this.steps), '')
        this.syncTaskState(te.name)
      } else if (event.type === 'text') {
        const ae: AgentTextEvent = event as AgentTextEvent
        this.startTypewriter(ae.content)
        this.saveRun('running', JSON.stringify(this.steps), ae.content)
      } else if (event.type === 'done') {
        this.finishFlow()
        this.saveRun('done', JSON.stringify(this.steps), this.aiResponse)
        this.syncTaskState('完成')
      } else if (event.type === 'error') {
        const ae: AgentErrorEvent = event as AgentErrorEvent
        this.startTypewriter('❌ ' + ae.error)
        this.finishFlow()
        this.saveRun('error', JSON.stringify(this.steps), ae.error)
        this.syncTaskState('出错')
      }
    })
  }

  // Publish task progress to other devices (手机 → 平板/手表), failures are silent
  private syncTaskState(currentStep: string): void {
    const payload: TaskStatePayload = {
      goal: this.goal,
      stepIndex: this.steps.length,
      stepCount: Math.max(this.steps.length, 1),
      currentStep: currentStep,
      status: this.flowStatus,
      updatedAt: new Date().toISOString()
    }
    distributedService.publishTaskState(payload)
  }

  private async saveRun(status: string, stepsJson: string, result: string): Promise<void> {
    if (this.currentRunId.length === 0) {
      return
    }
    try {
      const run: WorkflowRun = {
        id: this.currentRunId,
        goal: this.goal,
        status: status as ('running' | 'done' | 'error'),
        stepsJson: stepsJson,
        result: result,
        chatId: this.currentChatId,
        createdAt: this.runCreatedAt,
        updatedAt: new Date().toISOString()
      }
      await dbService.saveWorkflowRun(run)
    } catch (_e) {
      // persistence must never break the task
    }
  }

  finishFlow(): void {
    clearInterval(this.timer); this.timer = -1
    this.elapsed = Date.now() - this.startTime
    this.flowStatus = 'done'; this.allDone = true
    this.executing = false
  }

  startTypewriter(fullText: string): void {
    if (this.twTimer >= 0) { clearInterval(this.twTimer) }
    this.typedResponse = ''
    this.aiResponse = fullText
    let pos: number = 0
    const speed: number = fullText.length > 200 ? 8 : 12
    this.twTimer = setInterval(() => {
      pos++
      if (pos >= fullText.length) {
        this.typedResponse = fullText
        clearInterval(this.twTimer)
        this.twTimer = -1
      } else {
        this.typedResponse = fullText.substring(0, pos)
      }
    }, speed)
  }

  resetAll(): void {
    this.steps = []; this.goal = ''; this.aiResponse = ''
    this.typedResponse = ''
    this.progress = 0; this.flowStatus = 'idle'
    this.allDone = false; this.inputText = ''
    this.executing = false; this.elapsed = 0
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1 }
    if (this.twTimer >= 0) { clearInterval(this.twTimer); this.twTimer = -1 }
  }

  build() {
    Column() {
      // Header
      Row() {
        Image($r('sys.symbol.arrow_left'))
          .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
          .fillColor(this.col().textPrimary)
          .onClick(() => { router.back() })
        Text(this.goal || 'AI 任务')
          .fontSize($r('app.float.font_size_subtitle')).fontColor(this.col().textPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.Center).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').padding($r('app.float.spacing_md'))
      .backgroundColor(this.col().glassNav).backdropBlur(10)

      // Input area
      Row() {
        TextInput({ text: this.inputText, placeholder: '描述任务，让 AI 帮你完成...' })
          .layoutWeight(1).height(44).fontSize(15)
          .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
          .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_md'))
          .padding({ left: 16, right: 16 })
          .onChange((v: string) => { this.inputText = v })
          .onSubmit(() => { this.startAiFlow() })

        Button({ type: ButtonType.Circle }) {
          Text('→').fontSize(20).fontColor('#FFFFFF')
        }
        .width(44).height(44)
        .backgroundColor(this.inputText.trim().length > 0 ? this.col().accent : this.col().textTertiary)
        .margin({ left: 8 })
        .onClick(() => { this.startAiFlow() })
      }
      .width('100%')
      .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
        top: $r('app.float.spacing_sm'), bottom: $r('app.float.spacing_sm') })
      .backgroundColor(this.col().surfaceVariant)

      if (!this.hasApiKey) {
        Text('未配置 API Key，请在对话页设置')
          .fontSize($r('app.float.font_size_caption')).fontColor('#F59E0B')
          .width('100%')
          .padding({ left: $r('app.float.spacing_md'), top: $r('app.float.spacing_sm'),
            bottom: $r('app.float.spacing_sm') })
          .backgroundColor('rgba(245,158,11,0.08)')
      }

      // Progress bar
      if (this.steps.length > 0) {
        Row().width(this.progress + '%').height(3)
          .backgroundColor(this.col().accent).animation({ duration: 300, curve: Curve.EaseOut })
        Column().width('100%').height(1).backgroundColor(this.col().divider)
      }

      // Content area
      if (this.steps.length === 0 && this.flowStatus === 'idle') {
        // Empty state
        Column() {
          Column().height($r('app.float.spacing_xxl'))

          Image($r('app.media.icon_agent'))
            .width(72).height(72)
            .borderRadius(18)
            .opacity(0.9)
            .margin({ bottom: $r('app.float.spacing_md') })

          Text('AI 任务')
            .fontSize($r('app.float.font_size_title')).fontColor(this.col().textPrimary)
            .fontWeight(FontWeight.Bold).margin({ bottom: $r('app.float.spacing_xs') })

          Text('输入任务描述，AI 自主调用工具执行')
            .fontSize($r('app.float.font_size_body')).fontColor(this.col().textSecondary)
            .margin({ bottom: $r('app.float.spacing_lg') })

          Text('试试：')
            .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
            .margin({ bottom: $r('app.float.spacing_sm') })

          Row() {
            this.tag('查天气并保存')
            this.tag('创建项目')
            this.tag('设提醒')
          }
          .margin({ bottom: $r('app.float.spacing_sm') })

          if (this.showLastRun && this.lastRun) {
            Column() {
              Text(this.lastRun.goal)
                .fontSize($r('app.float.font_size_body'))
                .fontColor(this.col().textPrimary)
                .fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.lastRunStatusText(this.lastRun) + ' · ' + this.fmtTime(this.lastRun.updatedAt))
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.col().textTertiary)
                .width('100%')
                .margin({ top: 4 })
              Button('▶ 继续上次任务')
                .fontSize($r('app.float.font_size_caption'))
                .fontColor('#FFFFFF')
                .backgroundColor(this.col().accent)
                .borderRadius($r('app.float.radius_md'))
                .height(36)
                .margin({ top: $r('app.float.spacing_sm') })
                .onClick(() => { this.resumeLastRun() })
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().glassCard)
            .borderRadius($r('app.float.radius_lg'))
            .border({ width: 1, color: this.col().divider })
          }
        }
        .width('100%').layoutWeight(1).alignItems(HorizontalAlign.Center)
        .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg') })
        .backgroundColor(this.col().bg)
      }

      if (this.steps.length > 0 || this.flowStatus !== 'idle') {
        Column() {
          if (this.aiResponse.length > 0) {
            Column() {
              MarkdownText({
                content: this.typedResponse,
                textColor: this.col().textPrimary,
                accentColor: this.col().accent
              })
                .width('100%')
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().glassCard)
            .borderRadius($r('app.float.radius_lg'))
            .border({ width: 2, color: this.col().accent + '30' })
            .margin({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
              top: $r('app.float.spacing_md') })
          }

          Row() {
            Text('步骤')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              .fontWeight(FontWeight.Bold).layoutWeight(1)
            Text(this.steps.length + '步 · ' + (this.elapsed / 1000).toFixed(1) + 's')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
            top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

          List() {
            ForEach(this.steps, (step: AiStep, idx: number) => {
              ListItem() {
                Row() {
                  Text(step.status === TaskStatus.FAILED ? '✗' : '✓')
                    .fontSize(10).fontColor('#FFFFFF')
                    .width(22).height(22).borderRadius(11)
                    .backgroundColor(step.status === TaskStatus.FAILED ? '#EF4444' : '#10B981')
                    .textAlign(TextAlign.Center)
                    .margin({ right: $r('app.float.spacing_sm') })

                  Column() {
                    Text(step.name)
                      .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                    if (step.result.length > 0) {
                      Text(step.result.length > 80
                        ? step.result.substring(0, 80) + '...'
                        : step.result)
                        .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textSecondary)
                        .margin({ top: 2 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)
                }
                .width('100%')
                .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
                  top: $r('app.float.spacing_sm'), bottom: $r('app.float.spacing_sm') })
              }
            })
          }
          .width('100%').layoutWeight(1).backgroundColor(this.col().bg)
        }
        .width('100%').layoutWeight(1)
      }

      // Bottom bar
      if (this.steps.length > 0) {
        Row() {
          if (this.flowStatus === 'running') {
            LoadingProgress().width(16).height(16).color(this.col().accent).margin({ right: 10 })
            Text('AI 执行中...').fontSize(15).fontColor(this.col().textSecondary)
          } else if (this.allDone) {
            Button('↻ 重新执行')
              .fontSize($r('app.float.font_size_body')).fontColor('#FFFFFF')
              .backgroundColor(this.col().accent).borderRadius($r('app.float.radius_md'))
              .padding({ left: $r('app.float.spacing_xl'), right: $r('app.float.spacing_xl') })
              .onClick(() => { this.resetAll(); this.inputText = this.goal })
            Button('新任务')
              .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
              .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_md'))
              .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg') })
              .margin({ left: $r('app.float.spacing_sm') })
              .onClick(() => { this.resetAll() })
          }
        }
        .width('100%').padding($r('app.float.spacing_lg')).justifyContent(FlexAlign.Center)
        .backgroundColor(this.col().surface)
        .border({ width: { top: 1 }, color: this.col().divider })
      }
    }
    .width('100%').height('100%').backgroundColor(this.col().bg)
  }

  @Builder tag(text: string) {
    Text(text)
      .fontSize($r('app.float.font_size_caption'))
      .fontColor(this.col().accent)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.col().accent + '10')
      .borderRadius($r('app.float.radius_sm'))
      .margin({ right: $r('app.float.spacing_sm') })
      .onClick(() => { this.inputText = text; this.startAiFlow() })
  }

  lastRunStatusText(run: WorkflowRun): string {
    if (run.status === 'running') {
      return '⏸ 未完成（可续跑）'
    }
    if (run.status === 'error') {
      return '✗ 出错（可重试）'
    }
    return '✓ 已完成'
  }

  fmtTime(iso: string): string {
    try {
      const d: Date = new Date(iso)
      return (d.getMonth() + 1).toString().padStart(2, '0') + '-' +
        d.getDate().toString().padStart(2, '0') + ' ' +
        d.getHours().toString().padStart(2, '0') + ':' +
        d.getMinutes().toString().padStart(2, '0')
    } catch (_e) {
      return ''
    }
  }
}
