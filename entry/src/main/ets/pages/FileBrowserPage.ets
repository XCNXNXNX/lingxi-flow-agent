import { router } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { getFileBaseDir } from '../tools/FileTools'

interface FileEntry {
  name: string; isDir: boolean; size: number; mtime: number
}

@Entry
@Component
struct FileBrowserPage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State currentPath: string = ''
  @State entries: FileEntry[] = []
  @State pathHistory: string[] = []
  @State isLoading: boolean = false
  @State showNewDialog: boolean = false
  @State showActions: boolean = false
  @State newItemName: string = ''
  @State newItemIsDir: boolean = true
  @State actionEntry: FileEntry | null = null
  @State renameText: string = ''
  @State isRenaming: boolean = false
  @State pasteReady: boolean = false
  @State showEditor: boolean = false
  @State editContent: string = ''
  @State editEntry: FileEntry | null = null
  private clipboardPath: string = ''

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  aboutToAppear(): void { this.loadDir('') }
  onPageShow(): void { this.loadDir(this.currentPath) }

  build() {
    Stack() {
      Column() {
        Row() {
          Image($r('sys.symbol.arrow_left'))
            .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
            .fillColor(this.col().textPrimary)
            .onClick(() => { router.back() })
          Text('文件')
            .fontSize($r('app.float.font_size_subtitle'))
            .fontColor(this.col().textPrimary).fontWeight(FontWeight.Medium)
            .layoutWeight(1).textAlign(TextAlign.Center)
          Button('＋')
            .fontSize($r('app.float.font_size_body')).fontColor(this.col().accent)
            .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_sm'))
            .padding({ left: $r('app.float.spacing_sm'), right: $r('app.float.spacing_sm') })
            .onClick(() => { this.showNewDialog = true; this.newItemName = ''; this.newItemIsDir = true })
        }
        .width('100%').padding($r('app.float.spacing_md'))
        .backgroundColor(this.col().glassNav).backdropBlur(10)

        Row() {
          Text('/根' + (this.currentPath ? '/' + this.currentPath : ''))
            .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (this.pathHistory.length > 0) {
            Text('‹ 上级')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().accent)
              .onClick(() => { this.goBack() })
          }
        }
        .width('100%').padding({ left: $r('app.float.spacing_md'), right: $r('app.float.spacing_md'),
          top: $r('app.float.spacing_sm'), bottom: $r('app.float.spacing_sm') })
        .backgroundColor(this.col().surfaceVariant)

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.col().accent)
            Text('加载中...').fontSize($r('app.float.font_size_small')).fontColor(this.col().textTertiary)
              .margin({ top: $r('app.float.spacing_sm') })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.entries.length === 0) {
          Column() {
            Text('📂').fontSize(48).opacity(0.3).margin({ bottom: $r('app.float.spacing_md') })
            Text('目录为空').fontSize($r('app.float.font_size_body')).fontColor(this.col().textTertiary)
            Text('点击 ＋ 创建文件或文件夹').fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              .margin({ top: $r('app.float.spacing_sm') })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.entries, (entry: FileEntry) => {
              ListItem() {
                Row() {
                  Text(entry.isDir ? '📁' : '📄').fontSize(22).margin({ right: $r('app.float.spacing_sm') })
                  Column() {
                    Text(entry.name)
                      .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.fmtSize(entry.size) + ' · ' + this.fmtTime(entry.mtime))
                      .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('⋮')
                    .fontSize(20).fontColor(this.col().textTertiary)
                    .padding({ left: 8, right: 4, top: 4, bottom: 4 })
                    .onClick(() => { this.actionEntry = entry; this.showActions = true })
                }
                .width('100%').padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .border({ width: { bottom: 1 }, color: this.col().divider })
                .onClick(() => { if (entry.isDir) { this.enterDir(entry.name) } else { this.openEditor(entry) } })
              }
            })
          }
          .width('100%').layoutWeight(1).backgroundColor(this.col().bg)
        }
      }
      .width('100%').height('100%').backgroundColor(this.col().bg)

      // New item dialog overlay
      if (this.showNewDialog) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .onClick(() => { this.showNewDialog = false })

        Column() {
          Text('新建')
            .fontSize($r('app.float.font_size_subtitle')).fontWeight(FontWeight.Bold)
            .fontColor(this.col().textPrimary)
            .width('100%').margin({ bottom: $r('app.float.spacing_md') })

          Row() {
            Button('📁 文件夹')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.newItemIsDir ? '#FFFFFF' : this.col().textPrimary)
              .backgroundColor(this.newItemIsDir ? this.col().accent : this.col().surfaceVariant)
              .borderRadius($r('app.float.radius_sm'))
              .layoutWeight(1).margin({ right: $r('app.float.spacing_sm') })
              .onClick(() => { this.newItemIsDir = true })
            Button('📄 文件')
              .fontSize($r('app.float.font_size_body'))
              .fontColor(!this.newItemIsDir ? '#FFFFFF' : this.col().textPrimary)
              .backgroundColor(!this.newItemIsDir ? this.col().accent : this.col().surfaceVariant)
              .borderRadius($r('app.float.radius_sm'))
              .layoutWeight(1)
              .onClick(() => { this.newItemIsDir = false })
          }
          .width('100%').margin({ bottom: $r('app.float.spacing_md') })

          TextInput({ text: this.newItemName, placeholder: '名称...' })
            .fontSize($r('app.float.font_size_body')).width('100%')
            .backgroundColor(this.col().surfaceVariant)
            .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
            .borderRadius($r('app.float.radius_sm')).padding($r('app.float.spacing_sm'))
            .margin({ bottom: $r('app.float.spacing_md') })
            .onChange((v: string) => { this.newItemName = v })

          if (this.pasteReady) {
            Button('📋 粘贴已复制的文件')
              .fontSize($r('app.float.font_size_body')).fontColor(this.col().accent)
              .backgroundColor(this.col().surfaceVariant)
              .borderRadius($r('app.float.radius_md')).width('100%').height(40)
              .margin({ bottom: $r('app.float.spacing_md') })
              .onClick(() => { this.doPaste() })
          }

          Button('创建')
            .fontSize($r('app.float.font_size_body')).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            .backgroundColor(this.col().accent).borderRadius($r('app.float.radius_md'))
            .width('100%').height(44)
            .enabled(this.newItemName.trim().length > 0)
            .onClick(() => { this.doCreate() })
        }
        .width('85%').padding($r('app.float.spacing_xl'))
        .backgroundColor(this.col().surface)
        .borderRadius($r('app.float.radius_lg'))
        .border({ width: 1, color: this.col().divider })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 8 })
      }

      // Action sheet overlay
      if (this.showActions && this.actionEntry) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .onClick(() => { this.showActions = false; this.isRenaming = false })

        Column() {
          Text(this.actionEntry!.name)
            .fontSize($r('app.float.font_size_subtitle')).fontWeight(FontWeight.Bold)
            .fontColor(this.col().textPrimary)
            .width('100%').margin({ bottom: $r('app.float.spacing_md') })

          if (this.isRenaming) {
            TextInput({ text: this.renameText, placeholder: '新名称...' })
              .fontSize($r('app.float.font_size_body')).width('100%')
              .backgroundColor(this.col().surfaceVariant)
              .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
              .borderRadius($r('app.float.radius_sm')).padding($r('app.float.spacing_sm'))
              .margin({ bottom: $r('app.float.spacing_md') })
              .onChange((v: string) => { this.renameText = v })
            Row() {
              Button('确认重命名').fontSize($r('app.float.font_size_body')).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                .backgroundColor(this.col().accent).borderRadius($r('app.float.radius_md'))
                .layoutWeight(1).margin({ right: $r('app.float.spacing_sm') })
                .onClick(() => { this.doRename() })
              Button('取消').fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                .backgroundColor(this.col().surfaceVariant).borderRadius($r('app.float.radius_md')).layoutWeight(1)
                .onClick(() => { this.isRenaming = false })
            }
            .width('100%')
          } else {
            this.actBtn('📋 复制', () => { this.doCopy() })
            this.actBtn('✏️ 重命名', () => { this.renameText = this.actionEntry!.name; this.isRenaming = true })
            if (this.actionEntry && !this.actionEntry.isDir) {
              this.actBtn('📝 编辑', () => { this.showActions = false; this.openEditor(this.actionEntry!) })
            }
            this.actBtn('🗑 删除', () => { this.doDelete(); this.showActions = false }, true)
          }
        }
        .width('85%').padding($r('app.float.spacing_xl'))
        .backgroundColor(this.col().surface)
        .borderRadius($r('app.float.radius_lg'))
        .border({ width: 1, color: this.col().divider })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: -4 })
        .animation({ duration: 200, curve: Curve.EaseOut })
      }

      // File editor overlay
      if (this.showEditor && this.editEntry) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(this.col().bg)

        Column() {
          Row() {
            Text('✕ 返回')
              .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
              .onClick(() => { this.showEditor = false })
            Text(this.editEntry!.name)
              .fontSize($r('app.float.font_size_subtitle')).fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1).textAlign(TextAlign.Center).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('保存')
              .fontSize($r('app.float.font_size_caption')).fontColor('#FFFFFF')
              .backgroundColor(this.col().accent).borderRadius($r('app.float.radius_sm'))
              .padding({ left: 14, right: 14 })
              .onClick(() => { this.doSave() })
          }
          .width('100%').padding($r('app.float.spacing_md'))
          .backgroundColor(this.col().glassNav).backdropBlur(10)

          TextArea({ text: this.editContent, placeholder: '文件内容...' })
            .width('100%').layoutWeight(1)
            .fontSize(14).fontColor(this.col().textPrimary)
            .placeholderColor(this.col().textTertiary)
            .backgroundColor(this.col().bg)
            .padding($r('app.float.spacing_md'))
            .onChange((v: string) => { this.editContent = v })
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  actBtn(label: string, onClick: () => void, isDanger?: boolean) {
    Button(label)
      .fontSize($r('app.float.font_size_body'))
      .fontColor(isDanger ? '#DC2626' : this.col().textPrimary)
      .backgroundColor(this.col().surfaceVariant)
      .borderRadius($r('app.float.radius_md')).width('100%').height(44)
      .margin({ bottom: $r('app.float.spacing_sm') })
      .onClick(onClick)
  }

  private async loadDir(relPath: string): Promise<void> {
    this.isLoading = true; this.currentPath = relPath
    const base: string = getFileBaseDir()
    if (base.length === 0) { this.entries = []; this.isLoading = false; return }
    try {
      const fp: string = base + (relPath ? '/' + relPath : '')
      const names: string[] = await fileIo.listFile(fp)
      const list: FileEntry[] = []
      for (let i: number = 0; i < names.length; i++) {
        const ep: string = fp + '/' + names[i]
        const info = await fileIo.stat(ep)
        list.push({ name: names[i], isDir: info.isDirectory(), size: info.size, mtime: info.mtime })
      }
      this.entries = list
    } catch (err) { this.entries = [] }
    this.isLoading = false
  }

  private async openEditor(entry: FileEntry): Promise<void> {
    this.editEntry = entry
    const rel: string = this.currentPath ? this.currentPath + '/' + entry.name : entry.name
    try {
      const fp: string = getFileBaseDir() + '/' + rel
      this.editContent = fileIo.readTextSync(fp)
    } catch (_e) {
      this.editContent = ''
    }
    this.showEditor = true
  }

  private async doSave(): Promise<void> {
    if (!this.editEntry) { return }
    const rel: string = this.currentPath ? this.currentPath + '/' + this.editEntry.name : this.editEntry.name
    try {
      const fp: string = getFileBaseDir() + '/' + rel
      const file: fileIo.File = fileIo.openSync(fp,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, this.editContent)
      fileIo.closeSync(file)
    } catch (e) { /* ignore */ }
    this.showEditor = false
    this.loadDir(this.currentPath)
  }

  private enterDir(name: string): void {
    this.pathHistory.push(this.currentPath)
    this.currentPath = this.currentPath ? this.currentPath + '/' + name : name
    this.loadDir(this.currentPath)
  }

  private goBack(): void {
    if (this.pathHistory.length > 0) { this.currentPath = this.pathHistory.pop() || ''; this.loadDir(this.currentPath) }
  }

  private async doCreate(): Promise<void> {
    const name: string = this.newItemName.trim();
    if (!name) { return }
    try {
      const fp: string = getFileBaseDir() + '/' + this.currentPath + '/' + name
      if (this.newItemIsDir) { await fileIo.mkdir(fp, true) }
      else { const f = await fileIo.open(fp, 0o102); await fileIo.close(f) }
      this.showNewDialog = false; this.newItemName = ''
      this.loadDir(this.currentPath)
    } catch (err) { /* ignore */ }
  }

  private doCopy(): void {
    if (this.actionEntry) {
      const rel: string = this.currentPath ? this.currentPath + '/' + this.actionEntry.name : this.actionEntry.name
      this.clipboardPath = getFileBaseDir() + '/' + rel
      this.pasteReady = true
    }
    this.showActions = false
  }

  private async doPaste(): Promise<void> {
    if (!this.clipboardPath) { return }
    try {
      const srcStat = await fileIo.stat(this.clipboardPath)
      const destName: string = this.clipboardPath.split('/').pop() || 'pasted'
      const dest: string = getFileBaseDir() + '/' + this.currentPath + '/' + destName
      const sf = await fileIo.open(this.clipboardPath, 0)
      const buf: ArrayBuffer = new ArrayBuffer(srcStat.size > 0 ? srcStat.size : 4096)
      await fileIo.read(sf.fd, buf)
      await fileIo.close(sf)
      const df = await fileIo.open(dest, 0o102)
      await fileIo.write(df.fd, buf)
      await fileIo.close(df)
      this.showNewDialog = false; this.pasteReady = false
      this.loadDir(this.currentPath)
    } catch (err) { /* ignore */ }
  }

  private async doDelete(): Promise<void> {
    if (!this.actionEntry) { return }
    const rel: string = this.currentPath ? this.currentPath + '/' + this.actionEntry.name : this.actionEntry.name
    try {
      const fp: string = getFileBaseDir() + '/' + rel
      if (this.actionEntry.isDir) { await this.rmDir(fp) }
      else { await fileIo.unlink(fp) }
      this.loadDir(this.currentPath)
    } catch (err) { /* ignore */ }
  }

  private async doRename(): Promise<void> {
    const newName: string = this.renameText.trim()
    if (!newName || !this.actionEntry) { this.isRenaming = false; return }
    const oldRel: string = this.currentPath ? this.currentPath + '/' + this.actionEntry.name : this.actionEntry.name
    const newRel: string = this.currentPath ? this.currentPath + '/' + newName : newName
    try {
      const oldF: string = getFileBaseDir() + '/' + oldRel
      const newF: string = getFileBaseDir() + '/' + newRel
      if (this.actionEntry.isDir) {
        await fileIo.mkdir(newF)
        await this.cpDir(oldF, newF)
        await this.rmDir(oldF)
      } else {
        const f = await fileIo.open(oldF, 0)
        const info = await fileIo.stat(oldF)
        const buf: ArrayBuffer = new ArrayBuffer(info.size > 0 ? info.size : 1024)
        await fileIo.read(f.fd, buf)
        await fileIo.close(f)
        const d = await fileIo.open(newF, 0o102)
        await fileIo.write(d.fd, buf)
        await fileIo.close(d)
        await fileIo.unlink(oldF)
      }
      this.isRenaming = false; this.showActions = false
      this.loadDir(this.currentPath)
    } catch (err) { this.isRenaming = false }
  }

  private async cpDir(src: string, dest: string): Promise<void> {
    try {
      const files: string[] = await fileIo.listFile(src)
      for (let i: number = 0; i < files.length; i++) {
        const sub: string = src + '/' + files[i]
        const info = await fileIo.stat(sub)
        if (info.isDirectory()) { await fileIo.mkdir(dest + '/' + files[i]); await this.cpDir(sub, dest + '/' + files[i]) }
        else {
          const f = await fileIo.open(sub, 0)
          const buf: ArrayBuffer = new ArrayBuffer(info.size > 0 ? info.size : 1024)
          await fileIo.read(f.fd, buf)
          await fileIo.close(f)
          const d = await fileIo.open(dest + '/' + files[i], 0o102)
          await fileIo.write(d.fd, buf)
          await fileIo.close(d)
        }
      }
    } catch (err) { /* ignore */ }
  }

  private async rmDir(path: string): Promise<void> {
    try {
      const files: string[] = await fileIo.listFile(path)
      for (let i: number = 0; i < files.length; i++) {
        const sub: string = path + '/' + files[i]
        const info = await fileIo.stat(sub)
        if (info.isDirectory()) { await this.rmDir(sub) } else { await fileIo.unlink(sub) }
      }
      await fileIo.rmdir(path)
    } catch (err) { /* ignore */ }
  }

  private fmtSize(size: number): string {
    if (size < 1024) { return size + ' B' }
    if (size < 1048576) { return (size / 1024).toFixed(1) + ' KB' }
    return (size / 1048576).toFixed(1) + ' MB'
  }

  private fmtTime(mtime: number): string {
    const d: Date = new Date(mtime * 1000)
    return (d.getMonth() + 1).toString().padStart(2, '0') + '/' +
      d.getDate().toString().padStart(2, '0') + ' ' +
      d.getHours().toString().padStart(2, '0') + ':' +
      d.getMinutes().toString().padStart(2, '0')
  }
}
