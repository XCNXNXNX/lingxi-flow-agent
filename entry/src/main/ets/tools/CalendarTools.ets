// CalendarTools - Time/date tools for the agent
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'

const SCHEMA_TIME: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>
const SCHEMA_DATE: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>
const SCHEMA_WEEKDAY: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>

const WEEKDAYS: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']

export function registerCalendarTools(registry: ToolRegistry): void {
  registry.registerTool(
    'get_current_time',
    'Get the current time (hours, minutes, seconds)',
    SCHEMA_TIME,
    async (_input: Record<string, Object>): Promise<string> => {
      const now: Date = new Date()
      const h: string = now.getHours().toString().padStart(2, '0')
      const m: string = now.getMinutes().toString().padStart(2, '0')
      const s: string = now.getSeconds().toString().padStart(2, '0')
      return '当前时间: ' + h + ':' + m + ':' + s
    }
  )

  registry.registerTool(
    'get_current_date',
    'Get the current date (year, month, day)',
    SCHEMA_DATE,
    async (_input: Record<string, Object>): Promise<string> => {
      const now: Date = new Date()
      const y: number = now.getFullYear()
      const mo: string = (now.getMonth() + 1).toString().padStart(2, '0')
      const d: string = now.getDate().toString().padStart(2, '0')
      const wd: string = WEEKDAYS[now.getDay()]
      return '今天是 ' + y + '年' + mo + '月' + d + '日 ' + wd
    }
  )

  registry.registerTool(
    'get_weekday',
    'Get the current day of the week',
    SCHEMA_WEEKDAY,
    async (_input: Record<string, Object>): Promise<string> => {
      const now: Date = new Date()
      return '今天是' + WEEKDAYS[now.getDay()]
    }
  )

  Logger.info('CalendarTools', 'Registered 3 calendar tools')
}
