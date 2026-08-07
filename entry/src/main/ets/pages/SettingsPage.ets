import { router, promptAction } from '@kit.ArkUI'
import { ThemeService, ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { dbService } from '../engine/DatabaseService'
import { agentCore } from '../engine/AgentCore'
import { configService } from '../services/ConfigService'
import { skillPackService } from '../services/SkillPackService'
import { picker } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { SkillGroup, SkillToolInfo } from '../engine/ToolRegistry'
import { SkillPack } from '../model/Types'

interface MemoryItem {
  key: string
  value: string
}

// 提示词模板预设
const PROMPT_TEMPLATES: PromptTemplate[] = [
  { name: '默认助理', prompt: '' },
  { name: '学习助手', prompt: '你是灵犀，一位耐心的学习伙伴。回答时先给结论再展开解释，善于用例子和类比帮助理解，遇到难题会拆解成小步骤引导。学生问作业时，先引导思考而不是直接给答案。' },
  { name: '效率达人', prompt: '你是灵犀，一位雷厉风行的效率专家。收到任务立刻规划最短路径并执行，回复简洁直接、少客套，善于把模糊需求转化为可执行清单。' },
  { name: '贴心管家', prompt: '你是灵犀，一位细心周到的生活管家。主动记住用户的习惯与偏好（用记忆笔记保存），在合适的时候提醒用户，回复温暖亲切。' }
]

interface PromptTemplate {
  name: string
  prompt: string
}

@Entry
@Component
struct SettingsPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State memories: MemoryItem[] = []
  @State showMemories: boolean = false
  @State showSkills: boolean = false
  @State memoryText: string = ''
  @State skillGroups: SkillGroup[] = []
  @State promptText: string = ''
  @State promptSaved: boolean = false
  @State skillPacks: SkillPack[] = []
  @State showPacks: boolean = false
  @State packMsg: string = ''

  aboutToAppear(): void {
    this.loadSkills()
    this.loadMemoriesData()
    this.loadPrompt()
    this.loadPacks()
  }

  async loadPacks(): Promise<void> {
    this.skillPacks = skillPackService.getPacks()
  }

  async togglePack(name: string, enabled: boolean): Promise<void> {
    await skillPackService.setEnabled(name, enabled)
    await this.loadPacks()
  }

  async importPack(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const options: picker.DocumentSelectOptions = {
        fileSuffixFilters: ['.json']
      }
      const pickerInstance: picker.DocumentViewPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await pickerInstance.select(options)
      if (!uris || uris.length === 0) {
        return
      }
      const msg: string = await skillPackService.importFromUri(uris[0])
      this.packMsg = msg
      await this.loadPacks()
      promptAction.showToast({ message: msg, duration: 2500 })
    } catch (e) {
      promptAction.showToast({ message: '导入失败: ' + (e as Error).message, duration: 2500 })
    }
  }

  async exportPack(name: string): Promise<void> {
    const msg: string = await skillPackService.exportPack(name)
    promptAction.showToast({ message: msg, duration: 2500 })
  }

  async removePack(name: string): Promise<void> {
    await skillPackService.removePack(name)
    await this.loadPacks()
    promptAction.showToast({ message: '已删除技能包', duration: 1500 })
  }

  async loadSkills(): Promise<void> {
    const groups: SkillGroup[] = agentCore.getToolRegistry().getSkillGroups()
    this.skillGroups = groups
  }

  async loadMemoriesData(): Promise<void> {
    try {
      const keysStr: string | null = await dbService.getKV('memory_keys')
      if (!keysStr) { this.memories = []; return }
      const keys: string[] = JSON.parse(keysStr) as string[]
      const list: MemoryItem[] = []
      for (let i: number = 0; i < keys.length; i++) {
        const val: string | null = await dbService.getKV('mem_' + keys[i])
        if (val) { list.push({ key: keys[i], value: val }) }
      }
      this.memories = list
    } catch (e) { this.memories = [] }
  }

  toggleTool(name: string, enabled: boolean): void {
    agentCore.getToolRegistry().setToolEnabled(name, enabled)
    this.loadSkills()
  }

  getEnabledToolCount(): number {
    let count: number = 0
    for (let i: number = 0; i < this.skillGroups.length; i++) {
      const g: SkillGroup = this.skillGroups[i]
      for (let j: number = 0; j < g.tools.length; j++) {
        if (g.tools[j].enabled) {
          count++
        }
      }
    }
    return count
  }

  async loadPrompt(): Promise<void> {
    this.promptText = await configService.getSystemPrompt()
  }

  applyTemplate(name: string): void {
    for (let i: number = 0; i < PROMPT_TEMPLATES.length; i++) {
      if (PROMPT_TEMPLATES[i].name === name) {
        this.promptText = PROMPT_TEMPLATES[i].prompt
        return
      }
    }
  }

  async savePrompt(): Promise<void> {
    await configService.saveSystemPrompt(this.promptText.trim())
    this.promptSaved = true
    promptAction.showToast({ message: '提示词已保存，新对话生效', duration: 2000 })
    setTimeout(() => { this.promptSaved = false }, 2000)
  }

  async resetPrompt(): Promise<void> {
    this.promptText = ''
    await configService.saveSystemPrompt('')
    promptAction.showToast({ message: '已恢复默认提示词', duration: 2000 })
  }

  async saveMemory(): Promise<void> {
    const text: string = this.memoryText.trim()
    if (!text) { return }
    const key: string = 'm_' + Date.now()
    try {
      const keysStr: string | null = await dbService.getKV('memory_keys')
      const keys: string[] = keysStr ? JSON.parse(keysStr) as string[] : []
      keys.push(key)
      await dbService.setKV('memory_keys', JSON.stringify(keys))
      await dbService.setKV('mem_' + key, text)
      this.memoryText = ''
      await this.loadMemoriesData()
    } catch (e) { /* ignore */ }
  }

  async deleteMemory(key: string): Promise<void> {
    try {
      const keysStr: string | null = await dbService.getKV('memory_keys')
      if (keysStr) {
        const keys: string[] = JSON.parse(keysStr) as string[]
        const filtered: string[] = []
        for (let i: number = 0; i < keys.length; i++) {
          if (keys[i] !== key) { filtered.push(keys[i]) }
        }
        await dbService.setKV('memory_keys', JSON.stringify(filtered))
      }
      await dbService.setKV('mem_' + key, '')
    } catch (e) { /* ignore */ }
    await this.loadMemoriesData()
  }

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  build() {
    Column() {
      Row() {
        Image($r('sys.symbol.arrow_left'))
          .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
          .fillColor(this.col().textPrimary)
          .onClick(() => { router.back() })

        Text('设置')
          .fontSize($r('app.float.font_size_subtitle'))
          .fontColor(this.col().textPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.Center)
          .margin({ right: $r('app.float.icon_size_md') })
      }
      .width('100%').padding($r('app.float.spacing_md'))
      .backgroundColor(this.col().glassNav).backdropBlur(10)

      Scroll() {
        Column() {
          // Theme section
          Text('风格')
            .fontSize($r('app.float.font_size_body'))
            .fontColor(this.col().textPrimary)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .padding({ left: $r('app.float.spacing_lg'), top: $r('app.float.spacing_lg'),
              bottom: $r('app.float.spacing_sm') })

          this.themeBlock('🦞', '龙虾风格', '深色 · 珊瑚', 'lobster', this.col())
          this.themeBlock('🔮', '灵犀风格', '浅色 · 紫罗兰', 'lingxi', this.col())

          // API service entry
          Row() {
            Text('⚙')
              .fontSize(18).margin({ right: $r('app.float.spacing_sm') })
            Column() {
              Text('API 服务')
                .fontSize($r('app.float.font_size_body'))
                .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
              Text('API 库 / 服务商预设 / MCP 配置')
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.col().textTertiary).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›')
              .fontSize(18).fontColor(this.col().textTertiary)
          }
          .width('100%')
          .padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .border({ width: 1, color: this.col().divider })
          .margin({ top: $r('app.float.spacing_sm') })
          .onClick(() => { router.pushUrl({ url: 'pages/ApiSettingsPage' }) })

          // Memory section
          Row() {
            Text('记忆')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)

            Text(this.showMemories ? '收起' : '管理')
              .fontSize($r('app.float.font_size_small'))
              .fontColor(this.col().accent)
              .onClick(() => { this.showMemories = !this.showMemories; if (this.showMemories) { this.loadMemoriesData() }})
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })

          if (this.showMemories) {
            Column() {
              Row() {
                TextInput({ text: this.memoryText, placeholder: 'AI 应该记住什么...' })
                  .layoutWeight(1).height(40)
                  .fontColor(this.col().textPrimary)
                  .placeholderColor(this.col().textTertiary)
                  .backgroundColor(this.col().surfaceVariant)
                  .borderRadius($r('app.float.radius_sm'))
                  .padding({ left: 12, right: 12 })
                  .onChange((v: string): void => { this.memoryText = v })
                Button('记住')
                  .fontSize($r('app.float.font_size_caption'))
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.col().accent)
                  .borderRadius($r('app.float.radius_sm'))
                  .padding({ left: 12, right: 12 }).height(40).margin({ left: 8 })
                  .onClick(() => { this.saveMemory() })
              }
              .width('100%').padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg') })

              if (this.memories.length > 0) {
                ForEach(this.memories, (mem: MemoryItem): void => {
                  Row() {
                    Text(mem.value)
                      .fontSize($r('app.float.font_size_small'))
                      .fontColor(this.col().textSecondary)
                      .layoutWeight(1).maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Button('✕')
                      .fontSize(12).fontColor(this.col().textTertiary)
                      .backgroundColor('transparent')
                      .onClick(() => { this.deleteMemory(mem.key) })
                  }
                  .width('100%')
                  .padding($r('app.float.spacing_md'))
                  .backgroundColor(this.col().surfaceVariant)
                  .borderRadius($r('app.float.radius_md'))
                  .margin({ top: $r('app.float.spacing_sm') })
                })
              }
            }
            .width('100%')
            .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
              top: $r('app.float.spacing_sm') })
          }

          // Skills section (dynamic, from ToolRegistry)
          Row() {
            Text('技能')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Text(this.getEnabledToolCount() + '/' + this.skillGroups.length + ' 组 · ' +
              (this.showSkills ? '收起' : '管理'))
              .fontSize($r('app.float.font_size_small'))
              .fontColor(this.col().accent)
              .onClick(() => { this.showSkills = !this.showSkills })
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })

          if (this.showSkills) {
            Text('自由增删能力：关闭的技能将不再提供给 AI，即时生效')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .padding({ left: $r('app.float.spacing_lg'), top: $r('app.float.spacing_sm'),
                bottom: $r('app.float.spacing_sm') })

            ForEach(this.skillGroups, (group: SkillGroup) => {
              Column() {
                Row() {
                  Text(group.name)
                    .fontSize($r('app.float.font_size_body'))
                    .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
                  Blank()
                  Text(group.tools.length + ' 工具')
                    .fontSize($r('app.float.font_size_caption'))
                    .fontColor(this.col().textTertiary)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(this.col().surfaceVariant)
                    .borderRadius($r('app.float.radius_sm'))
                }
                .width('100%').margin({ bottom: $r('app.float.spacing_xs') })

                ForEach(group.tools, (tool: SkillToolInfo) => {
                  Row() {
                    Text(tool.name)
                      .fontSize($r('app.float.font_size_small'))
                      .fontColor(tool.enabled ? this.col().textPrimary : this.col().textTertiary)
                      .layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Toggle({ type: ToggleType.Switch, isOn: tool.enabled })
                      .selectedColor(this.col().accent)
                      .onChange((isOn: boolean): void => { this.toggleTool(tool.name, isOn) })
                  }
                  .width('100%').padding({ top: 2, bottom: 2 })
                })
              }
              .width('100%')
              .padding($r('app.float.spacing_md'))
              .backgroundColor(this.col().surface)
              .borderRadius($r('app.float.radius_md'))
              .border({ width: 1, color: this.col().divider })
              .margin({ top: $r('app.float.spacing_sm') })
            })
          }

          // Custom system prompt section
          Row() {
            Text('AI 提示词')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Text('自定义角色设定，新对话生效')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })

          Column() {
            Scroll() {
              TextArea({ text: this.promptText, placeholder: '在这里描述你想要的 AI 人设与行为准则…（留空 = 默认助理）' })
                .width('100%').height(140)
                .fontSize($r('app.float.font_size_small'))
                .fontColor(this.col().textPrimary)
                .placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant)
                .borderRadius($r('app.float.radius_md'))
                .padding(8)
                .onChange((v: string): void => { this.promptText = v })
            }
            .width('100%').height(140)

            Row() {
              Text('模板')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              ForEach(PROMPT_TEMPLATES, (tpl: PromptTemplate) => {
                Text(tpl.name)
                  .fontSize($r('app.float.font_size_caption'))
                  .fontColor(this.promptText === tpl.prompt ? this.col().accent : this.col().textSecondary)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.col().surfaceVariant)
                  .borderRadius($r('app.float.radius_sm'))
                  .margin({ left: $r('app.float.spacing_xs') })
                  .onClick(() => { this.applyTemplate(tpl.name) })
              })
            }
            .width('100%').margin({ top: $r('app.float.spacing_sm') })

            Row() {
              Button('恢复默认')
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.col().textSecondary)
                .backgroundColor(this.col().surfaceVariant)
                .borderRadius($r('app.float.radius_sm')).height(32)
                .onClick(() => { this.resetPrompt() })
              Button('保存')
                .fontSize($r('app.float.font_size_caption')).fontColor('#FFFFFF')
                .backgroundColor(this.col().accent)
                .borderRadius($r('app.float.radius_sm')).height(32)
                .margin({ left: $r('app.float.spacing_sm') })
                .onClick(() => { this.savePrompt() })
            }
            .width('100%').justifyContent(FlexAlign.End).margin({ top: $r('app.float.spacing_sm') })
          }
          .width('100%')
          .padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .border({ width: 1, color: this.col().divider })
          .margin({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_sm') })

          // Skill packs section (JSON skill packages, shareable)
          Row() {
            Text('技能包')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Text(this.showPacks ? '收起' : '管理')
              .fontSize($r('app.float.font_size_small'))
              .fontColor(this.col().accent)
              .onClick(() => { this.showPacks = !this.showPacks })
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })

          if (this.showPacks) {
            Text('技能包是 JSON 文件：导入他人分享的包，或导出自己的配置分享出去')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .padding({ left: $r('app.float.spacing_lg'), top: $r('app.float.spacing_sm'),
                bottom: $r('app.float.spacing_sm') })

            Row() {
              Button('导入技能包')
                .fontSize($r('app.float.font_size_caption')).fontColor('#FFFFFF')
                .backgroundColor(this.col().accent)
                .borderRadius($r('app.float.radius_sm')).height(32)
                .onClick(() => { this.importPack() })
              Text('从文件/聊天中选择 .json 技能包')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .margin({ left: $r('app.float.spacing_sm') })
            }
            .width('100%')
            .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
              bottom: $r('app.float.spacing_sm') })

            if (this.skillPacks.length === 0) {
              Text('暂无技能包')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .width('100%').textAlign(TextAlign.Center)
                .padding($r('app.float.spacing_md'))
            } else {
              ForEach(this.skillPacks, (pack: SkillPack) => {
                Column() {
                  Row() {
                    Column() {
                      Text(pack.displayName)
                        .fontSize($r('app.float.font_size_body'))
                        .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
                      Text(pack.description)
                        .fontSize($r('app.float.font_size_small'))
                        .fontColor(this.col().textTertiary).margin({ top: 2 })
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start).layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: pack.enabled })
                      .selectedColor(this.col().accent)
                      .onChange((isOn: boolean): void => { this.togglePack(pack.name, isOn) })
                  }
                  .width('100%')

                  Row() {
                    Text('v' + pack.version + ' · ' + pack.author)
                      .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                    Blank()
                    Text('导出')
                      .fontSize($r('app.float.font_size_caption')).fontColor(this.col().accent)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .onClick(() => { this.exportPack(pack.name) })
                    Text('删除')
                      .fontSize($r('app.float.font_size_caption')).fontColor('#DC2626')
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .onClick(() => { this.removePack(pack.name) })
                  }
                  .width('100%').margin({ top: $r('app.float.spacing_sm') })
                }
                .width('100%')
                .padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .borderRadius($r('app.float.radius_md'))
                .border({ width: 1, color: this.col().divider })
                .margin({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
                  top: $r('app.float.spacing_sm') })
              })
            }
          }

          // Device collaboration entry
          Row() {
            Image($r('app.media.icon_device_1'))
              .width(20).height(20)
              .objectFit(ImageFit.Contain)
              .margin({ right: $r('app.float.spacing_sm') })
            Column() {
              Text('跨设备协同')
                .fontSize($r('app.float.font_size_body'))
                .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
              Text('发现附近设备，同步任务进度与提醒')
                .fontSize($r('app.float.font_size_small'))
                .fontColor(this.col().textTertiary).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(18).fontColor(this.col().textTertiary)
          }
          .width('100%')
          .padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .border({ width: 1, color: this.col().divider })
          .margin({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })
          .onClick(() => { router.pushUrl({ url: 'pages/DevicePage' }) })

          // Knowledge base entry
          Row() {
            Text('📚').fontSize(18).margin({ right: $r('app.float.spacing_sm') })
            Column() {
              Text('知识库管理')
                .fontSize($r('app.float.font_size_body'))
                .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
              Text('查看已索引文档，重建知识索引')
                .fontSize($r('app.float.font_size_small'))
                .fontColor(this.col().textTertiary).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(18).fontColor(this.col().textTertiary)
          }
          .width('100%')
          .padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .border({ width: 1, color: this.col().divider })
          .margin({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })
          .onClick(() => { router.pushUrl({ url: 'pages/KnowledgePage' }) })

          Column().height($r('app.float.spacing_xxl'))
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(this.col().bg)
    }
    .width('100%').height('100%')
    .backgroundColor(this.col().bg)
  }

  @Builder
  themeBlock(icon: string, name: string, desc: string, key: ThemeStyle, colors: ThemeColors) {
    Row() {
      Text(icon).fontSize(28).margin({ right: $r('app.float.spacing_md') })

      Column() {
        Text(name)
          .fontSize($r('app.float.font_size_body'))
          .fontColor(colors.textPrimary)
          .fontWeight(this.currentTheme === key ? FontWeight.Bold : FontWeight.Normal)
        Text(desc)
          .fontSize($r('app.float.font_size_small'))
          .fontColor(colors.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (this.currentTheme === key) {
        Text('✓')
          .fontSize(16)
          .fontColor(colors.accent)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_lg'))
    .backgroundColor(this.currentTheme === key ? colors.glassCard : colors.surface)
    .borderRadius($r('app.float.radius_lg'))
    .border({
      width: this.currentTheme === key ? 2 : 1,
      color: this.currentTheme === key ? colors.accent : colors.divider
    })
    .margin({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
      bottom: $r('app.float.spacing_sm') })
    .animation({ duration: 180 })
    .onClick(async (): Promise<void> => {
      await ThemeService.setStyle(key)
    })
  }
}
