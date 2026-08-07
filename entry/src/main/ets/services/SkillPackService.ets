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
  },
  {
    schemaVersion: 1,
    name: 'daily_news',
    displayName: '今日新闻',
    version: '1.0.0',
    description: '搜索官方权威媒体，为用户简述今日要闻；指定领域（科技/财经/体育等）时专注该领域权威媒体',
    author: 'Lingxi Team',
    tags: ['资讯'],
    prompt: '技能「今日新闻」：当用户说"今日新闻/看看新闻/有什么新闻"时：\n1) 先判断用户是否指定了领域（科技/财经/体育/国际/娱乐/健康/军事/房产等）。指定了 → 专注该领域权威媒体；没指定 → 综合要闻。\n2) 用 web_search 搜索权威媒体，按领域选择（每轮至少 2 次搜索覆盖不同媒体）：\n- 综合：site:news.cn 今日要闻、site:people.com.cn 今日头条、site:cctv.com 今日新闻\n- 科技：site:ithome.com、site:36kr.com、site:people.com.cn 科技\n- 财经：site:yicai.com、site:caixin.com 快讯、site:finance.sina.com.cn 今日\n- 体育：site:sports.cctv.com、site:sports.sina.com.cn 今日\n- 国际：site:news.cn 国际新闻、site:huanqiu.com 今日\n- 娱乐：site:ent.people.com.cn、site:ent.sina.com.cn\n- 健康：site:health.people.com.cn、site:jiankang.cctv.com\n3) 对最重要的 1-2 条，用 web_fetch 抓取原文确认细节。\n4) 输出格式：先列最重要的 3-5 条（每条 = 标题 + 一句话摘要 + 来源媒体），其余列标题清单；结尾一句点评今日焦点。\n5) 若用户说"详细讲讲XX"，用 web_fetch 抓原文详细讲述。\n6) 用 memory_write 记住用户常看的领域（如"用户关注科技新闻"），下次自动侧重该领域。',
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
    prompt: '技能「出行助手」：当用户说"要去XX/出行/旅行"时：1) get_current_date 确认日期，get_weather 查目的地近期天气；2) web_search 查目的地攻略（交通/景点/门票/美食，至少 2 次搜索）；3) 输出行程规划：日期+天气、交通方式、每日安排、必去景点、美食推荐；4) 用 write_file 保存为"出行计划-<目的地>.md"；5) 问用户是否需要出发提醒，需要则 create_reminder 设置。',
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
    prompt: '技能「健康管家」：当用户说"健康/喝水/久坐/养生"时：1) memory_read 查看用户的健康目标和历史打卡；2) 按需设置提醒：喝水（每 60 分钟 create_reminder）、久坐起身（每 90 分钟）、睡眠（用户指定时间）；3) 用户问健康知识时用 web_search 查权威来源（site:health.people.com.cn 或 site:who.int 中文）；4) 用户打卡时用 memory_write 记录（"健康打卡：<日期> <内容>"）；5) 汇总今日健康建议。',
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
    prompt: '技能「财经速递」：当用户说"股市/大盘/财经/汇率"时：1) 用 web_search 查权威财经源：site:finance.sina.com.cn 今日 A股、site:yicai.com 今日财经、site:caixin.com 快讯；2) 用户问具体股票/基金时，追加搜索该标的；3) 输出：大盘概况（指数涨跌）、板块热点 2-3 个、重要财经新闻 2-3 条、汇率（如需要）；4) 结尾加一句风险提示（"以上仅为资讯汇总，不构成投资建议"）。',
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
    prompt: '技能「影视推荐」：当用户说"电影/剧/好看/推荐"时：1) 确认用户口味（类型/新片或经典/平台），可用 memory_read 找历史偏好；2) web_search 查豆瓣热映口碑与高分片单（site:movie.douban.com 本周热映、site:movie.douban.com 高分）；3) 推荐 3-5 部：片名 + 评分 + 一句话简介 + 看点 + 观看平台；4) 用 memory_write 记住用户口味偏好。',
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
    prompt: '技能「美食菜谱」：当用户说"做饭/菜谱/吃什么/怎么做"时：1) 确认食材（用户报的食材或冰箱存货）或口味偏好（川菜/清淡/快手等）；2) web_search 查菜谱（site:xiachufang.com <菜名>、site:meishij.net <菜名>做法）；3) 输出 2-3 道菜：菜名 + 所需食材 + 步骤清单（编号）+ 预计用时；4) 用户说"食材只有XX"时用已有食材推荐。',
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
    prompt: '技能「睡前仪式」：当用户说"晚安/睡觉/睡前"时：1) 用 memory_read 回顾今天的关键事件；2) 帮用户写今日总结（完成的事、未完成的事）；3) 规划明日 1-3 件最重要的事，问用户明早提醒时间；4) create_reminder 设置明早提醒（如"明早 7:30 提醒：<明日要事>"）；5) 用 memory_write 保存"今日总结+明日计划"；6) 温柔道晚安。',
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
    prompt: '技能「灵感速记」：当用户说"记一下/记下来/灵感/待办"时：1) 判断内容类型（灵感/待办/备忘）；2) 用 memory_write 保存为"<类型>：<内容>"，关键词提炼 2-3 个便于检索；3) 待办类追加 create_reminder 提醒（问用户时间或默认当天 20:00）；4) 回复"已记下"+ 关键词 + 后续可随时问"我的灵感"来回顾。',
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
