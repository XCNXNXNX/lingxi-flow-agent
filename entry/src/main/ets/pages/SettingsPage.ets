import { router } from '@kit.ArkUI'
import { ThemeService, ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { dbService } from '../engine/DatabaseService'

interface MemoryItem {
  key: string
  value: string
}

@Entry
@Component
struct SettingsPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State memories: MemoryItem[] = []
  @State showMemories: boolean = false
  @State showSkills: boolean = false
  @State memoryText: string = ''
  @State skillList: SkillEntry[] = []

  aboutToAppear(): void {
    this.loadSkills()
    this.loadMemoriesData()
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

  loadSkills(): void {
    this.skillList = [
      { name: '基础读写', desc: '创建/读取/写入/删除/搜索/复制/粘贴文件', count: 8, active: true },
      { name: '提醒功能', desc: '创建/列出/取消提醒，系统通知', count: 3, active: true },
      { name: '网页搜索', desc: 'DuckDuckGo 搜索 + 网页抓取', count: 2, active: true },
      { name: '记忆笔记', desc: 'Markdown 笔记读写', count: 3, active: true },
      { name: '周期任务', desc: '定时/周期执行 AI 任务', count: 3, active: true },
      { name: '日历管理', desc: '系统日历日程创建/查询 + 时间/日期/星期', count: 5, active: true }
    ]
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

          // Skills section
          Row() {
            Text('技能')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Text(this.showSkills ? '收起' : '查看')
              .fontSize($r('app.float.font_size_small'))
              .fontColor(this.col().accent)
              .onClick(() => { this.showSkills = !this.showSkills })
          }
          .width('100%')
          .padding({ left: $r('app.float.spacing_lg'), right: $r('app.float.spacing_lg'),
            top: $r('app.float.spacing_lg') })

          if (this.showSkills) {
            Text('AI 可自主调用以下技能')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .padding({ left: $r('app.float.spacing_lg'), top: $r('app.float.spacing_sm'),
                bottom: $r('app.float.spacing_sm') })

            ForEach(this.skillList, (skill: SkillEntry): void => {
              Row() {
                Circle()
                  .width(8).height(8)
                  .fill(skill.active ? '#10B981' : this.col().textTertiary)
                  .margin({ right: $r('app.float.spacing_sm') })

                Column() {
                  Text(skill.name)
                    .fontSize($r('app.float.font_size_body'))
                    .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
                  Text(skill.desc)
                    .fontSize($r('app.float.font_size_small'))
                    .fontColor(this.col().textTertiary).margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)

                Text(skill.count + ' 工具')
                  .fontSize($r('app.float.font_size_caption'))
                  .fontColor(skill.active ? this.col().accent : this.col().textTertiary)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(this.col().surfaceVariant)
                  .borderRadius($r('app.float.radius_sm'))
              }
              .width('100%')
              .padding($r('app.float.spacing_md'))
              .backgroundColor(this.col().surface)
              .borderRadius($r('app.float.radius_md'))
              .border({ width: 1, color: this.col().divider })
              .margin({ top: $r('app.float.spacing_sm') })
            })
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

interface SkillEntry {
  name: string
  desc: string
  count: number
  active: boolean
}
