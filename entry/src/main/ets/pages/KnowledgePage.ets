// KnowledgePage - RAG knowledge base management
// Shows indexed sources, index mode/status, rebuild & delete controls
import { router } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import { ragService, SourceFileInfo } from '../engine/RagService'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'

@Entry
@Component
struct KnowledgePage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State files: SourceFileInfo[] = []
  @State chunkCount: number = 0
  @State mode: string = '未初始化'
  @State isBuilding: boolean = false
  @State toastMsg: string = ''

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  async aboutToAppear(): Promise<void> {
    await this.refreshAll()
  }

  async refreshAll(): Promise<void> {
    this.files = await ragService.getSourceFiles()
    this.chunkCount = await ragService.getChunkCount()
    const status: string = ragService.getStatus()
    if (status === 'ready') {
      this.mode = '向量检索（BGE-M3）'
    } else if (status === 'fallback') {
      this.mode = '关键词检索（未配置嵌入 Key）'
    } else if (status === 'indexing') {
      this.mode = '索引构建中...'
    } else {
      this.mode = '未初始化'
    }
  }

  async rebuild(): Promise<void> {
    this.isBuilding = true
    this.mode = '索引构建中...'
    await ragService.forceRebuild()
    await this.refreshAll()
    this.isBuilding = false
  }

  async deleteFile(item: SourceFileInfo): Promise<void> {
    // item.name format: 记忆/xxx.md | 知识库/xxx.md | 根目录/xxx.md
    const slash: number = item.name.indexOf('/')
    if (slash <= 0) {
      return
    }
    const dir: string = item.name.substring(0, slash)
    const name: string = item.name.substring(slash + 1)
    let relPath: string = ''
    if (dir === '记忆') {
      relPath = '/memory/' + name
    } else if (dir === '知识库') {
      relPath = '/knowledge/' + name
    } else {
      relPath = '/' + name
    }
    try {
      await fileIo.unlink(ragService.getFilesDir() + relPath)
      ragService.markDirty()
      await this.refreshAll()
    } catch (e) {
      this.toastMsg = '删除失败: ' + (e as Error).message
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Image($r('sys.symbol.arrow_left'))
          .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
          .fillColor(this.col().textPrimary)
          .onClick(() => { router.back() })
        Text('知识库')
          .fontSize($r('app.float.font_size_subtitle'))
          .fontColor(this.col().textPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button('重建')
          .fontSize($r('app.float.font_size_caption'))
          .fontColor(this.col().accent)
          .backgroundColor(this.col().surfaceVariant)
          .borderRadius($r('app.float.radius_sm'))
          .padding({ left: $r('app.float.spacing_sm'), right: $r('app.float.spacing_sm') })
          .enabled(!this.isBuilding)
          .onClick(() => { this.rebuild() })
      }
      .width('100%').padding($r('app.float.spacing_md'))
      .backgroundColor(this.col().glassNav).backdropBlur(10)

      Scroll() {
        Column() {
          // Status card
          Column() {
            Row() {
              Circle()
                .width(10).height(10)
                .fill(this.mode.indexOf('未') === 0 ? this.col().textTertiary : this.col().accent)
                .margin({ right: $r('app.float.spacing_sm') })
              Text(this.mode)
                .fontSize($r('app.float.font_size_body'))
                .fontColor(this.col().textPrimary)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
            }
            Row() {
              Text('已索引 ' + this.chunkCount + ' 个内容块')
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.col().textSecondary)
              Blank()
              Text(this.files.length + ' 个源文件')
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.col().textSecondary)
            }
            .width('100%').margin({ top: $r('app.float.spacing_sm') })
          }
          .width('100%')
          .padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().glassCard)
          .borderRadius($r('app.float.radius_lg'))
          .border({ width: 1, color: this.col().divider })

          // Hint
          Text('AI 会自动检索以下位置的文档来回答问题：\n· 记忆/（AI 笔记）\n· 知识库/（放入你的资料）\n· 根目录 .md / .txt')
            .fontSize($r('app.float.font_size_small'))
            .fontColor(this.col().textTertiary)
            .width('100%')
            .margin({ top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

          if (this.toastMsg.length > 0) {
            Text(this.toastMsg)
              .fontSize($r('app.float.font_size_small'))
              .fontColor('#DC2626')
              .margin({ bottom: $r('app.float.spacing_sm') })
          }

          // File list
          if (this.files.length === 0) {
            Column() {
              Text('📚').fontSize(40).opacity(0.4).margin({ bottom: $r('app.float.spacing_sm') })
              Text('知识库为空')
                .fontSize($r('app.float.font_size_body')).fontColor(this.col().textTertiary)
              Text('在文件管理器中创建 knowledge 文件夹放入资料')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .margin({ top: $r('app.float.spacing_xs') })
            }
            .width('100%').padding({ top: $r('app.float.spacing_xl') })
          } else {
            ForEach(this.files, (item: SourceFileInfo) => {
              Row() {
                Text(item.name.indexOf('记忆') === 0 ? '🧠' : '📄')
                  .fontSize(18).margin({ right: $r('app.float.spacing_sm') })
                Column() {
                  Text(item.name)
                    .fontSize($r('app.float.font_size_body'))
                    .fontColor(this.col().textPrimary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.fmtSize(item.size))
                    .fontSize($r('app.float.font_size_caption'))
                    .fontColor(this.col().textTertiary)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('✕')
                  .fontSize(14).fontColor(this.col().textTertiary)
                  .padding({ left: 10, right: 4, top: 4, bottom: 4 })
                  .onClick(() => { this.deleteFile(item) })
              }
              .width('100%')
              .padding($r('app.float.spacing_md'))
              .backgroundColor(this.col().surface)
              .border({ width: { bottom: 1 }, color: this.col().divider })
            })
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md') })
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(this.col().bg)
    }
    .width('100%').height('100%').backgroundColor(this.col().bg)
  }

  private fmtSize(size: number): string {
    if (size < 1024) { return size + ' B' }
    if (size < 1048576) { return (size / 1024).toFixed(1) + ' KB' }
    return (size / 1048576).toFixed(1) + ' MB'
  }
}
