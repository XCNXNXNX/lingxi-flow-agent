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
    prompt: '技能「每日简报」：用户说"生成今日简报"时：1) get_current_date 确认日期；2) get_weather 查天气；3) calendar_query 查日程；4) write_file 写入"今日简报.md"；5) 告知文件位置。',
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
    prompt: '技能「会议助手」：用户说"安排会议/开会"时：1) 确认时间地点；2) calendar_create 建日程；3) create_reminder 设提前10分钟提醒；4) write_file 建"会议纪要-主题.md"模板；5) 汇报。',
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
    prompt: '技能「番茄专注」：用户说"开始番茄钟"时：create_reminder 设25分钟专注提醒，到时再设5分钟休息提醒，汇报计划。',
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
    prompt: '技能「天气管家」：问天气时 get_weather 查询（没给城市先 memory_read 找常用城市，找不到则询问），给温度/穿衣建议；用户明确常用城市时 memory_write 记住。',
    requires: ['get_weather', 'memory_read', 'memory_write'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'daily_news',
    displayName: '今日新闻',
    version: '1.0.0',
    description: '搜索官方权威媒体，为用户简述今日要闻；指定领域（科技/财经/体育等）时专注该领域权威媒体',
    author: 'Lingxi Team',
    tags: ['资讯'],
    prompt: '技能「今日新闻」：用户说"今日新闻"时：1) 判断是否指定领域（科技/财经/体育/国际/娱乐/健康）；2) web_search 权威媒体（综合:site:news.cn、site:people.com.cn、site:cctv.com；科技:site:ithome.com、site:36kr.com；财经:site:yicai.com、site:caixin.com；体育:site:sports.cctv.com；国际:site:huanqiu.com；娱乐:site:ent.people.com.cn；健康:site:health.people.com.cn）；3) 重要新闻 web_fetch 抓原文；4) 输出"标题+一句话摘要+来源"，先列3-5条重点；5) memory_write 记用户常看领域。',
    requires: ['web_search', 'web_fetch', 'memory_write', 'memory_read'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'travel_guide',
    displayName: '出行助手',
    version: '1.0.0',
    description: '目的地天气 + 交通攻略 + 行程规划，一键生成出行清单',
    author: 'Lingxi Team',
    tags: ['生活', '旅行'],
    prompt: '技能「出行助手」：用户说"去XX/旅行"时：1) get_weather 查目的地天气；2) web_search 查攻略（交通/景点/门票/美食）；3) 输出行程（日期/交通/每日安排/美食）；4) write_file 存"出行计划-目的地.md"；5) 问是否要出发提醒（create_reminder）。',
    requires: ['get_weather', 'get_current_date', 'web_search', 'write_file', 'create_reminder'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'health_guard',
    displayName: '健康管家',
    version: '1.0.0',
    description: '喝水/久坐/睡眠提醒，健康知识查询，打卡记录',
    author: 'Lingxi Team',
    tags: ['健康'],
    prompt: '技能「健康管家」：用户说"健康/喝水/久坐"时：1) memory_read 看健康目标；2) create_reminder 设喝水(60分钟)/起身(90分钟)提醒；3) 健康知识用 web_search 查权威源(site:health.people.com.cn)；4) 打卡用 memory_write 记录；5) 汇总建议。',
    requires: ['create_reminder', 'memory_read', 'memory_write', 'web_search', 'get_current_time'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'finance_daily',
    displayName: '财经速递',
    version: '1.0.0',
    description: '大盘行情、板块热点、汇率，权威财经媒体速览',
    author: 'Lingxi Team',
    tags: ['财经'],
    prompt: '技能「财经速递」：用户说"股市/财经/汇率"时：web_search 查 site:finance.sina.com.cn 今日A股、site:yicai.com 财经快讯；输出大盘概况+板块热点+重要新闻2-3条+汇率；结尾加"不构成投资建议"。',
    requires: ['web_search', 'web_fetch'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'movie_finder',
    displayName: '影视推荐',
    version: '1.0.0',
    description: '热映口碑、高分片单，按口味推荐电影剧集',
    author: 'Lingxi Team',
    tags: ['娱乐'],
    prompt: '技能「影视推荐」：用户说"电影/推荐"时：1) 确认口味（可 memory_read）；2) web_search 查豆瓣(site:movie.douban.com 热映/高分)；3) 推荐3-5部：片名+评分+简介+平台；4) memory_write 记口味。',
    requires: ['web_search', 'memory_read', 'memory_write'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'recipe_master',
    displayName: '美食菜谱',
    version: '1.0.0',
    description: '按食材/口味推荐菜谱，输出详细步骤清单',
    author: 'Lingxi Team',
    tags: ['生活'],
    prompt: '技能「美食菜谱」：用户说"做饭/菜谱"时：确认食材或口味，web_search 查 site:xiachufang.com 菜谱，输出2-3道菜：菜名+食材+步骤+用时。',
    requires: ['web_search'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'night_routine',
    displayName: '睡前仪式',
    version: '1.0.0',
    description: '睡前总结今日、规划明日，设置明早提醒',
    author: 'Lingxi Team',
    tags: ['效率', '健康'],
    prompt: '技能「睡前仪式」：用户说"晚安/睡前"时：1) memory_read 回顾今天；2) 写今日总结+明日计划；3) create_reminder 设明早提醒；4) memory_write 保存；5) 道晚安。',
    requires: ['memory_read', 'memory_write', 'create_reminder', 'get_current_time'],
    enabled: true
  },
  {
    schemaVersion: 1,
    name: 'quick_capture',
    displayName: '灵感速记',
    version: '1.0.0',
    description: '一句话记录灵感/待办/想法，自动分类归档',
    author: 'Lingxi Team',
    tags: ['效率'],
    prompt: '技能「灵感速记」：用户说"记一下/灵感/待办"时：memory_write 存"类型：内容"并提炼关键词；待办类问时间后 create_reminder 提醒；回复"已记下"。',
    requires: ['memory_write', 'create_reminder'],
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
    // Seed/backfill builtin packs by name (missing ones only, never overwrite user edits)
    let seeded: number = 0
    for (let i: number = 0; i < BUILTIN_PACKS.length; i++) {
      if (!this.findPack(BUILTIN_PACKS[i].name)) {
        await this.writePack(BUILTIN_PACKS[i])
        seeded++
      }
    }
    if (seeded > 0) {
      await this.reload()
      Logger.info('SkillPackService', 'seeded/backfilled ' + seeded + ' builtin packs')
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
