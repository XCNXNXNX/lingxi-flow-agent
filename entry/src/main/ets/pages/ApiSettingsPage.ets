// ApiSettingsPage - API service management
// Tab 1: API library (provider presets + profile form + saved profiles with quick switch)
// Tab 2: MCP server config (separated from plain API config)
import { router, promptAction } from '@kit.ArkUI'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { configService, PROVIDER_PRESETS } from '../services/ConfigService'
import { ApiProfile, ProviderPreset } from '../model/Types'

@Entry
@Component
struct ApiSettingsPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State tab: number = 0
  @State profiles: ApiProfile[] = []
  @State activeId: string = ''
  @State editingId: string = ''
  @State formName: string = ''
  @State formProvider: string = ''
  @State formBaseUrl: string = ''
  @State formApiKey: string = ''
  @State formModel: string = ''
  @State formEmbedKey: string = ''
  @State mcpUrl: string = ''
  @State mcpSaved: boolean = false
  @State fastMode: boolean = false

  private col(): ThemeColors {
    return getThemeColors(this.currentTheme)
  }

  aboutToAppear(): void {
    this.reload()
  }

  async reload(): Promise<void> {
    this.profiles = configService.getProfiles()
    const active: ApiProfile | null = await configService.getActiveProfile()
    this.activeId = active ? active.id : ''
    this.mcpUrl = await configService.getMcpUrl()
    this.fastMode = await configService.getFastMode()
    // Prefill form with active profile if form is empty
    if (active && this.formBaseUrl.length === 0) {
      this.fillForm(active)
    }
  }

  async toggleFastMode(enabled: boolean): Promise<void> {
    await configService.saveFastMode(enabled)
    promptAction.showToast({ message: enabled ? '已开启极速模式：纯对话秒回（工具暂不可用）' : '已关闭极速模式：工具已恢复', duration: 2500 })
  }

  fillForm(p: ApiProfile): void {
    this.editingId = p.id
    this.formName = p.name
    this.formProvider = p.provider
    this.formBaseUrl = p.baseUrl
    this.formApiKey = p.apiKey
    this.formModel = p.model
    this.formEmbedKey = p.embedKey
  }

  applyPreset(preset: ProviderPreset): void {
    this.editingId = ''
    this.formName = preset.name
    this.formProvider = preset.name
    this.formBaseUrl = preset.baseUrl
    this.formModel = preset.model
    this.formApiKey = ''
    promptAction.showToast({ message: '已填入 ' + preset.name + ' 地址，只需填写 API Key', duration: 2000 })
  }

  async saveProfile(): Promise<void> {
    const name: string = this.formName.trim()
    const baseUrl: string = this.formBaseUrl.trim()
    if (baseUrl.length === 0) {
      promptAction.showToast({ message: '请填写 API 地址（或选择上方服务商预设）', duration: 2000 })
      return
    }
    if (this.formApiKey.trim().length === 0) {
      promptAction.showToast({ message: '请填写 API Key', duration: 2000 })
      return
    }
    const existing: ApiProfile | null = this.editingId.length > 0 ? this.findProfile(this.editingId) : null
    const profile: ApiProfile = {
      id: existing ? existing.id : 'p_' + Date.now(),
      name: name.length > 0 ? name : (this.formProvider.length > 0 ? this.formProvider : '自定义'),
      provider: this.formProvider.length > 0 ? this.formProvider : '自定义',
      baseUrl: baseUrl,
      apiKey: this.formApiKey.trim(),
      model: this.formModel.trim().length > 0 ? this.formModel.trim() : 'deepseek-chat',
      maxTokens: 8192,
      temperature: 0.7,
      embedKey: this.formEmbedKey.trim(),
      embedUrl: ''
    }
    await configService.saveProfile(profile)
    await this.reload()
    promptAction.showToast({ message: '已保存并启用：' + profile.name, duration: 2000 })
  }

  private findProfile(id: string): ApiProfile | null {
    for (let i: number = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === id) {
        return this.profiles[i]
      }
    }
    return null
  }

  async switchProfile(id: string): Promise<void> {
    if (id === this.activeId) {
      return
    }
    await configService.setActiveProfileId(id)
    await this.reload()
    const p: ApiProfile | null = this.findProfile(id)
    promptAction.showToast({ message: '已切换：' + (p ? p.name : '') + '（新对话生效）', duration: 2000 })
  }

  confirmDelete(id: string): void {
    const p: ApiProfile | null = this.findProfile(id)
    AlertDialog.show({
      title: '删除配置',
      message: '确定删除「' + (p ? p.name : '') + '」吗？删除后不可恢复。',
      autoCancel: true,
      primaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: (): void => { this.doDelete(id) }
      },
      secondaryButton: {
        value: '取消',
        fontColor: '#666666',
        action: (): void => {}
      },
      cancel: (): void => {}
    })
  }

  async doDelete(id: string): Promise<void> {
    await configService.deleteProfile(id)
    await this.reload()
    promptAction.showToast({ message: '已删除', duration: 1500 })
  }

  async saveMcp(): Promise<void> {
    await configService.saveMcpUrl(this.mcpUrl.trim())
    this.mcpSaved = true
    promptAction.showToast({ message: 'MCP 地址已保存，重启后生效', duration: 2000 })
    setTimeout(() => { this.mcpSaved = false }, 2000)
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize($r('app.float.font_size_caption'))
      .fontColor(this.col().textTertiary)
      .width('100%')
      .margin({ top: $r('app.float.spacing_sm'), bottom: 4 })
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('‹')
          .fontSize(26).fontColor(this.col().textPrimary)
          .padding({ left: 8, right: 8 })
          .onClick(() => { router.back() })
        Text('API 服务')
          .fontSize($r('app.float.font_size_subtitle'))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.col().textPrimary)
          .layoutWeight(1)
        Text(this.activeId.length > 0 ? '使用中' : '未配置')
          .fontSize($r('app.float.font_size_caption'))
          .fontColor(this.activeId.length > 0 ? '#047857' : this.col().textTertiary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.activeId.length > 0 ? 'rgba(4,120,87,0.12)' : this.col().surfaceVariant)
          .borderRadius($r('app.float.radius_sm'))
      }
      .width('100%')
      .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
        top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

      // Tabs: API service | MCP config
      Row() {
        Text('API 服务')
          .fontSize($r('app.float.font_size_body'))
          .fontWeight(this.tab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.tab === 0 ? this.col().accent : this.col().textSecondary)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.tab === 0 ? 'rgba(59,130,246,0.12)' : this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .onClick(() => { this.tab = 0 })
        Text('MCP 配置')
          .fontSize($r('app.float.font_size_body'))
          .fontWeight(this.tab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.tab === 1 ? this.col().accent : this.col().textSecondary)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.tab === 1 ? 'rgba(59,130,246,0.12)' : this.col().surface)
          .borderRadius($r('app.float.radius_md'))
          .margin({ left: $r('app.float.spacing_sm') })
          .onClick(() => { this.tab = 1 })
      }
      .width('100%')
      .padding({ left: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

      Scroll() {
        Column() {
          if (this.tab === 0) {
            // ============ API SERVICE TAB ============

            // Active profile summary
            Row() {
              Text('当前使用')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              Blank()
              Text(this.activeId.length > 0 ? this.activeName() : '未配置 API，聊天功能不可用')
                .fontSize($r('app.float.font_size_small'))
                .fontColor(this.activeId.length > 0 ? this.col().textPrimary : '#DC2626')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().surface)
            .borderRadius($r('app.float.radius_md'))
            .border({ width: 1, color: this.col().divider })

            // Provider presets
            Text('服务商预设（点选自动填充，无需手填地址）')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .margin({ top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

            Scroll() {
              Row() {
                ForEach(PROVIDER_PRESETS, (preset: ProviderPreset) => {
                  Column() {
                    Text(preset.name)
                      .fontSize($r('app.float.font_size_small'))
                      .fontColor(this.formProvider === preset.name ? '#FFFFFF' : this.col().textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text(preset.note)
                      .fontSize(10)
                      .fontColor(this.formProvider === preset.name ? 'rgba(255,255,255,0.8)' : this.col().textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Center)
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  .backgroundColor(this.formProvider === preset.name ? this.col().accent : this.col().surfaceVariant)
                  .borderRadius($r('app.float.radius_md'))
                  .margin({ right: $r('app.float.spacing_sm') })
                  .onClick(() => { this.applyPreset(preset) })
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')

            // Form
            Text('配置' + (this.editingId.length > 0 ? '（编辑中）' : ''))
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .margin({ top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

            Column() {
              this.fieldLabel('配置名称')
              TextInput({ text: this.formName, placeholder: '如：DeepSeek 主力 / 公司内网' })
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.formName = v })

              this.fieldLabel('API 地址（Base URL）')
              TextInput({ text: this.formBaseUrl, placeholder: 'https://api.deepseek.com/v1' })
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.formBaseUrl = v })

              this.fieldLabel('API Key')
              TextInput({ text: this.formApiKey, placeholder: 'sk-...' })
                .type(InputType.Password)
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.formApiKey = v })

              this.fieldLabel('模型')
              TextInput({ text: this.formModel, placeholder: 'deepseek-chat' })
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.formModel = v })

              this.fieldLabel('嵌入 Key（可选，RAG 知识库用，如 SiliconFlow）')
              TextInput({ text: this.formEmbedKey, placeholder: 'sk-...（留空则用关键词检索）' })
                .type(InputType.Password)
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.formEmbedKey = v })
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().surface)
            .borderRadius($r('app.float.radius_md'))
            .border({ width: 1, color: this.col().divider })

            Button('保存到 API 库')
              .fontSize($r('app.float.font_size_body'))
              .backgroundColor(this.col().accent).fontColor('#FFFFFF')
              .borderRadius($r('app.float.radius_md'))
              .width('100%').height(44)
              .margin({ top: $r('app.float.spacing_md') })
              .onClick(() => { this.saveProfile() })

            // Fast mode: pure chat - lightweight requests queue much faster
            Row() {
              Column() {
                Text('极速模式')
                  .fontSize($r('app.float.font_size_body'))
                  .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
                Text('纯对话模式：不加载工具定义，请求更轻、响应更快（工具/技能不可用）')
                  .fontSize($r('app.float.font_size_caption'))
                  .fontColor(this.col().textTertiary).margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.fastMode })
                .selectedColor(this.col().accent)
                .onChange((isOn: boolean): void => { this.toggleFastMode(isOn) })
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().surface)
            .borderRadius($r('app.float.radius_md'))
            .border({ width: 1, color: this.col().divider })
            .margin({ top: $r('app.float.spacing_md') })

            // API library
            Text('API 库（点击卡片切换，新对话生效）')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')
              .margin({ top: $r('app.float.spacing_lg'), bottom: $r('app.float.spacing_sm') })

            if (this.profiles.length === 0) {
              Text('暂无已保存的配置。选择上方服务商预设并填写 Key 后保存。')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .width('100%').textAlign(TextAlign.Center)
                .padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .borderRadius($r('app.float.radius_md'))
                .border({ width: 1, color: this.col().divider })
            } else {
              ForEach(this.profiles, (p: ApiProfile) => {
                Row() {
                  Column() {
                    Row() {
                      Text(p.name)
                        .fontSize($r('app.float.font_size_body'))
                        .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
                      Text(p.provider)
                        .fontSize(10)
                        .fontColor(this.col().accent)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor('rgba(59,130,246,0.1)')
                        .borderRadius($r('app.float.radius_sm'))
                        .margin({ left: $r('app.float.spacing_xs') })
                    }
                    Text(p.model + ' · ' + this.shortenUrl(p.baseUrl))
                      .fontSize($r('app.float.font_size_caption'))
                      .fontColor(this.col().textTertiary).margin({ top: 3 })
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)

                  if (p.id === this.activeId) {
                    Text('使用中')
                      .fontSize(10).fontColor('#047857')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor('rgba(4,120,87,0.12)')
                      .borderRadius($r('app.float.radius_sm'))
                  } else {
                    Text('切换')
                      .fontSize(10).fontColor(this.col().accent)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor('rgba(59,130,246,0.1)')
                      .borderRadius($r('app.float.radius_sm'))
                  }

                  Text('编辑')
                    .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textSecondary)
                    .padding({ left: 8, right: 4, top: 3, bottom: 3 })
                  Text('删除')
                    .fontSize($r('app.float.font_size_caption')).fontColor('#DC2626')
                    .padding({ left: 4, right: 4, top: 3, bottom: 3 })
                }
                .width('100%')
                .padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .borderRadius($r('app.float.radius_md'))
                .border({ width: 1, color: p.id === this.activeId ? this.col().accent : this.col().divider })
                .margin({ top: $r('app.float.spacing_sm') })
                .onClick(() => {
                  if (p.id === this.activeId) {
                    this.fillForm(p)
                  } else {
                    this.switchProfile(p.id)
                  }
                })
              })
            }
          } else {
            // ============ MCP CONFIG TAB ============

            Text('MCP（Model Context Protocol）远程工具服务器。配置后 AI 可调用服务器提供的远程工具，重启应用生效。')
              .fontSize($r('app.float.font_size_caption'))
              .fontColor(this.col().textTertiary)
              .width('100%')

            Column() {
              this.fieldLabel('MCP 服务器地址')
              TextInput({ text: this.mcpUrl, placeholder: 'http://192.168.x.x:8080/mcp' })
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
                .onChange((v: string): void => { this.mcpUrl = v })
            }
            .width('100%')
            .padding($r('app.float.spacing_md'))
            .backgroundColor(this.col().surface)
            .borderRadius($r('app.float.radius_md'))
            .border({ width: 1, color: this.col().divider })
            .margin({ top: $r('app.float.spacing_md') })

            Row() {
              Text('快捷预设')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .margin({ right: $r('app.float.spacing_sm') })
              Button('鸿蒙官方文档')
                .fontSize($r('app.float.font_size_caption')).fontColor('#FFFFFF')
                .backgroundColor(this.col().accent)
                .borderRadius($r('app.float.radius_sm')).height(28)
                .onClick(() => {
                  this.mcpUrl = 'https://connect-api.cloud.huawei.com/api/developerknowledge/mcp'
                  promptAction.showToast({ message: '已填入鸿蒙官方文档 MCP，保存后重启生效', duration: 2500 })
                })
            }
            .width('100%').margin({ top: $r('app.float.spacing_md') })

            Button(this.mcpSaved ? '已保存 ✓' : '保存 MCP 配置')
              .fontSize($r('app.float.font_size_body'))
              .backgroundColor(this.col().accent).fontColor('#FFFFFF')
              .borderRadius($r('app.float.radius_md'))
              .width('100%').height(44)
              .margin({ top: $r('app.float.spacing_md') })
              .onClick(() => { this.saveMcp() })
          }
        }
        .width('100%')
        .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
          bottom: $r('app.float.spacing_lg') })
      }
      .width('100%').layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
    .backgroundColor(this.col().surface)
  }

  private activeName(): string {
    const p: ApiProfile | null = this.findProfile(this.activeId)
    return p ? p.name + ' · ' + p.model : '未配置'
  }

  private shortenUrl(url: string): string {
    if (url.length <= 28) {
      return url
    }
    return url.substring(0, 28) + '…'
  }
}
