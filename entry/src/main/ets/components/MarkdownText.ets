// MarkdownText - Simple markdown renderer for AI responses
// Strips **bold**, *italic*, `code` markers, renders headings/lists

@Component
export struct MarkdownText {
  @Prop content: string = ''
  @Prop textColor: string = '#1E293B'
  @Prop accentColor: string = '#4F46E5'

  private stripInline(text: string): string {
    let result: string = text
    while (true) {
      const start: number = result.indexOf('**')
      if (start < 0) { break }
      const end: number = result.indexOf('**', start + 2)
      if (end < 0) { break }
      result = result.substring(0, start) + result.substring(start + 2, end) + result.substring(end + 2)
    }
    while (true) {
      const start: number = result.indexOf('*')
      if (start < 0) { break }
      const end: number = result.indexOf('*', start + 1)
      if (end < 0) { break }
      result = result.substring(0, start) + result.substring(start + 1, end) + result.substring(end + 1)
    }
    while (true) {
      const start: number = result.indexOf('`')
      if (start < 0) { break }
      const end: number = result.indexOf('`', start + 1)
      if (end < 0) { break }
      result = result.substring(0, start) + result.substring(start + 1, end) + result.substring(end + 1)
    }
    return result
  }

  build() {
    Column() {
      if (!this.content || this.content.length === 0) {
        Text('')
      } else {
        ForEach(this.parseLines(), (line: MdLine) => {
          if (line.type === 0) {
            Text(line.text)
              .fontSize(15).fontColor(this.textColor)
              .wordBreak(WordBreak.BREAK_ALL)
              .margin({ bottom: 6 })
          } else if (line.type === 1) {
            Text(line.text)
              .fontSize(20).fontColor(this.textColor).fontWeight(FontWeight.Bold)
              .wordBreak(WordBreak.BREAK_ALL)
              .margin({ top: 10, bottom: 6 })
          } else if (line.type === 2) {
            Text(line.text)
              .fontSize(17).fontColor(this.textColor).fontWeight(FontWeight.Bold)
              .wordBreak(WordBreak.BREAK_ALL)
              .margin({ top: 8, bottom: 4 })
          } else if (line.type === 3) {
            Text(line.text)
              .fontSize(16).fontColor(this.textColor).fontWeight(FontWeight.Bold)
              .wordBreak(WordBreak.BREAK_ALL)
              .margin({ top: 6, bottom: 4 })
          } else if (line.type === 4) {
            Text('• ' + line.text)
              .fontSize(15).fontColor(this.textColor)
              .wordBreak(WordBreak.BREAK_ALL)
              .margin({ bottom: 4 })
          }
        })
      }
    }
    .constraintSize({ maxWidth: '100%' }).alignItems(HorizontalAlign.Start)
  }

  private parseLines(): MdLine[] {
    const result: MdLine[] = []
    if (!this.content || this.content.length === 0) {
      return result
    }
    const lines: string[] = this.content.split('\n')
    for (let i: number = 0; i < lines.length; i++) {
      const trimmed: string = lines[i].trim()
      if (trimmed.length === 0) {
        continue
      }
      if (trimmed.startsWith('### ') && trimmed.length > 4) {
        result.push({ type: 3, text: this.stripInline(trimmed.substring(4)) })
      } else if (trimmed.startsWith('## ') && trimmed.length > 3) {
        result.push({ type: 2, text: this.stripInline(trimmed.substring(3)) })
      } else if (trimmed.startsWith('# ') && trimmed.length > 2) {
        result.push({ type: 1, text: this.stripInline(trimmed.substring(2)) })
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        result.push({ type: 4, text: this.stripInline(trimmed.substring(2)) })
      } else {
        result.push({ type: 0, text: this.stripInline(trimmed) })
      }
    }
    return result
  }
}

interface MdLine {
  type: number
  text: string
}
