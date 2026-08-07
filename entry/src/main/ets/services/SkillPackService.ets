// SkillPackService - JSON skill pack system (share as files, OpenClaw-style)
// A skill pack is a single JSON file that bundles a persona prompt + required tools:
//   { "schemaVersion": 1, "name", "displayName", "version", "description",
//     "author", "tags", "prompt", "requires": [tool names], "enabled": true }
// Packs live in filesDir/skills/*.json; users can import via document picker,
// export to share, enable/disable, and delete. Enabled packs' prompts are injected
// into the system prompt, so the AI gains new behaviors without new executors.
import { fileIo } from '@kit.CoreFileKit'
import { picker } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'
import { SkillPack } from '../model/Types'

const BUILTIN_PACKS: SkillPack[] = [
  {
    schemaVersion: 1,
    name: 'daily_brief',
    displayName: '每日简报',
    version: '1.0.0',
    description: '一句话生成今日简报：日期、天气、日程、待办写入文件',
    author: 'Lingxi Team',
    tags: ['效率'],
    prompt: '技能「每日简报」：当用户说"生成今日简报/每日简报"时，依次执行：1) get_current_date 确认日期；2) get_weather 查询今天天气；3) calendar_query 查询未来日程；4) 汇总后用 write_file 写入"今日简报.md"（包含日期、天气、日程、问候语），并告诉用户文件已生成。',
    requires: ['get_current_date', 'get_weather', 'calendar_query', 'write_file'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'meeting_assistant',
    displayName: '会议助手',
    version: '1.0.0',
    description: '安排会议：创建日历日程、设置提前提醒、生成会议纪要模板',
    author: 'Lingxi Team',
    tags: ['办公'],
    prompt: '技能「会议助手」：当用户说"安排会议/开会"时：1) 确认时间地点（必要时用 get_current_date/get_current_time 推算）；2) calendar_create 创建日程（含 duration_minutes）；3) create_reminder 设置提前 10 分钟提醒；4) 用 write_file 创建"会议纪要-<主题>.md"模板文件；5) 汇报全部完成事项。',
    requires: ['calendar_create', 'create_reminder', 'write_file', 'get_current_date'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'pomodoro',
    displayName: '番茄专注',
    version: '1.0.0',
    description: '番茄工作法：25 分钟专注 + 5 分钟休息循环提醒',
    author: 'Lingxi Team',
    tags: ['效率', '健康'],
    prompt: '技能「番茄专注」：当用户说"开始番茄钟/专注25分钟"时：1) create_reminder 设置 25 分钟专注提醒（minutes=25）；2) 提示用户专注期间勿打扰；3) 专注结束后 create_reminder 设置 5 分钟休息提醒；4) 汇报专注计划。',
    requires: ['create_reminder', 'get_current_time'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'weather_guard',
    displayName: '天气管家',
    version: '1.0.0',
    description: '查询天气并给出穿衣/出行建议，自动记住常用城市',
    author: 'Lingxi Team',
    tags: ['生活'],
    prompt: '技能「天气管家」：当用户问天气时：1) get_weather 查询（用户没给城市时，先 memory_read 找"常用城市"记忆，找不到则询问）；2) 给出温度/天气/风力 + 穿衣和出行建议；3) 若用户明确表示某个城市是常用城市，用 memory_write 记住。',
    requires: ['get_weather', 'memory_read', 'memory_write'],
    enabled: true
  }
]

export class SkillPackService {
  private filesDir: string = ''
  private context: common.UIAbilityContext | null = null
  private packs: SkillPack[] = []

  async init(context: common.UIAbilityContext, filesDir: string): Promise<void> {
    this.context = context
    this.filesDir = filesDir + '/skills'
    try {
      fileIo.mkdirSync(this.filesDir, true)
    } catch (_e) {
      // already exists
    }
    await this.reload()
    // First launch: seed builtin packs
    if (this.packs.length === 0) {
      for (let i: number = 0; i < BUILTIN_PACKS.length; i++) {
        await this.writePack(BUILTIN_PACKS[i])
      }
      await this.reload()
      Logger.info('SkillPackService', 'seeded ' + BUILTIN_PACKS.length + ' builtin packs')
    }
  }

  getPacks(): SkillPack[] {
    return this.packs.slice(0)
  }

  getEnabledPacksPrompt(): string {
    let out: string = ''
    for (let i: number = 0; i < this.packs.length; i++) {
      const p: SkillPack = this.packs[i]
      if (p.enabled && p.prompt.length > 0) {
        out += '【技能包：' + p.displayName + '】' + p.prompt + '\n'
      }
    }
    return out.trim()
  }

  // Scan skills/*.json
  async reload(): Promise<void> {
    this.packs = []
    try {
      const names: string[] = fileIo.listFileSync(this.filesDir)
      for (let i: number = 0; i < names.length; i++) {
        if (!names[i].endsWith('.json')) {
          continue
        }
        try {
          const content: string = fileIo.readTextSync(this.filesDir + '/' + names[i])
          const pack: SkillPack | null = this.validate(JSON.parse(content) as Record<string, Object>)
          if (pack) {
            this.packs.push(pack)
          }
        } catch (_e) {
          Logger.warn('SkillPackService', 'skip invalid pack: ' + names[i])
        }
      }
    } catch (_e) {
      // dir missing
    }
    Logger.info('SkillPackService', 'loaded ' + this.packs.length + ' packs')
  }

  // Import a pack from a user-selected JSON file (document picker uri)
  async importFromUri(uri: string): Promise<string> {
    try {
      const text: string = fileIo.readTextSync(uri)
      const pack: SkillPack | null = this.validate(JSON.parse(text) as Record<string, Object>)
      if (!pack) {
        return '技能包格式无效（缺少 name/displayName/description/prompt）'
      }
      await this.writePack(pack)
      await this.reload()
      return '已导入技能包：' + pack.displayName + ' v' + pack.version
    } catch (e) {
      return '导入失败: ' + (e as Error).message
    }
  }

  // Export a pack to a user-chosen location (document picker save)
  async exportPack(name: string): Promise<string> {
    const pack: SkillPack | undefined = this.findPack(name)
    if (!pack) {
      return '未找到技能包: ' + name
    }
    if (!this.context) {
      return '导出失败: 未初始化'
    }
    try {
      const options: picker.DocumentSaveOptions = {
        newFileNames: [pack.name + '.json']
      }
      const pickerInstance: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context)
      const uris: string[] = await pickerInstance.save(options)
      if (!uris || uris.length === 0) {
        return '已取消导出'
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, JSON.stringify(pack, null, 2))
      fileIo.closeSync(file)
      return '已导出: ' + pack.name + '.json（可通过文件管理器/聊天分享）'
    } catch (e) {
      return '导出失败: ' + (e as Error).message
    }
  }

  async setEnabled(name: string, enabled: boolean): Promise<void> {
    const pack: SkillPack | undefined = this.findPack(name)
    if (!pack) {
      return
    }
    pack.enabled = enabled
    await this.writePack(pack)
    await this.reload()
  }

  async removePack(name: string): Promise<void> {
    try {
      fileIo.unlinkSync(this.filesDir + '/' + name + '.json')
    } catch (_e) {
      // ignore
    }
    await this.reload()
  }

  // Validate a parsed JSON object into a SkillPack, or null
  private validate(obj: Record<string, Object>): SkillPack | null {
    const name: string = (obj['name'] as string) || ''
    const displayName: string = (obj['displayName'] as string) || ''
    const description: string = (obj['description'] as string) || ''
    const prompt: string = (obj['prompt'] as string) || ''
    if (name.length === 0 || displayName.length === 0 || description.length === 0 || prompt.length === 0) {
      return null
    }
    const pack: SkillPack = {
      schemaVersion: (obj['schemaVersion'] as number) || 1,
      name: name,
      displayName: displayName,
      version: (obj['version'] as string) || '1.0.0',
      description: description,
      author: (obj['author'] as string) || 'unknown',
      tags: (obj['tags'] as string[]) || [],
      prompt: prompt,
      requires: (obj['requires'] as string[]) || [],
      enabled: (obj['enabled'] as boolean) !== false
    }
    return pack
  }

  private findPack(name: string): SkillPack | undefined {
    for (let i: number = 0; i < this.packs.length; i++) {
      if (this.packs[i].name === name) {
        return this.packs[i]
      }
    }
    return undefined
  }

  private async writePack(pack: SkillPack): Promise<void> {
    const file: fileIo.File = fileIo.openSync(this.filesDir + '/' + pack.name + '.json',
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, JSON.stringify(pack))
    fileIo.closeSync(file)
  }
}

export const skillPackService: SkillPackService = new SkillPackService()
