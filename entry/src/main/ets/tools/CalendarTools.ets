// CalendarTools - Time/date tools + system calendar events via @kit.CalendarKit
// calendar_create / calendar_query read & write the system calendar (user_grant permission)
import { calendarManager } from '@kit.CalendarKit'
import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'

let gContext: common.UIAbilityContext | null = null
let gCalendar: calendarManager.Calendar | null = null

export function initCalendarTools(context: common.UIAbilityContext): void {
  gContext = context
  gCalendar = null
}

const SCHEMA_TIME: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>
const SCHEMA_DATE: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>
const SCHEMA_WEEKDAY: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>

const SCHEMA_CREATE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"title":{"type":"string","description":"Event title, e.g. 开会"},"description":{"type":"string","description":"Event description"},"start_time":{"type":"number","description":"Start time as epoch milliseconds (use when the user gives an absolute time like 下午3点 or 明天)"},"minutes_from_now":{"type":"number","description":"Start in N minutes from now (use when the user says X分钟后/半小时后)"},"duration_minutes":{"type":"number","description":"Duration in minutes (default 60)"}},"required":["title"]}') as Record<string, Object>

const SCHEMA_QUERY: Record<string, Object> = JSON.parse('{"type":"object","properties":{"days":{"type":"number","description":"Query calendar events for the next N days (default 7)"}},"required":[]}') as Record<string, Object>

const WEEKDAYS: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']

// READ_CALENDAR / WRITE_CALENDAR are user_grant permissions - request at tool runtime
async function ensureCalendarPermission(): Promise<boolean> {
  if (!gContext) {
    return false
  }
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const res: PermissionRequestResult = await atManager.requestPermissionsFromUser(
      gContext, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'] as Permissions[])
    if (res.authResults && res.authResults.length >= 2) {
      return res.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        res.authResults[1] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    }
    return false
  } catch (e) {
    Logger.warn('CalendarTools', 'permission request failed: ' + (e as Error).message)
    return false
  }
}

async function getCalendar(): Promise<calendarManager.Calendar> {
  if (!gContext) {
    throw new Error('日历服务未初始化')
  }
  if (gCalendar) {
    return gCalendar
  }
  const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(gContext)
  gCalendar = await mgr.getCalendar()
  return gCalendar
}

function formatEventTime(ms: number): string {
  const d: Date = new Date(ms)
  return (d.getMonth() + 1).toString().padStart(2, '0') + '-' +
    d.getDate().toString().padStart(2, '0') + ' ' +
    d.getHours().toString().padStart(2, '0') + ':' +
    d.getMinutes().toString().padStart(2, '0')
}

async function calendarCreate(input: Record<string, Object>): Promise<string> {
  const title: string = (input['title'] as string) || ''
  if (title.length === 0) {
    return 'Error: title is required'
  }
  const desc: string = (input['description'] as string) || ''
  const durationMin: number = parseInt(String(input['duration_minutes'] === undefined ? '60' : input['duration_minutes'])) || 60

  let startMs: number = Date.now()
  if (input['start_time'] !== undefined) {
    const st: number = parseInt(String(input['start_time'])) || 0
    if (st > 0) {
      startMs = st
    }
  } else if (input['minutes_from_now'] !== undefined) {
    const mn: number = parseInt(String(input['minutes_from_now'])) || 0
    startMs = Date.now() + mn * 60000
  }

  const granted: boolean = await ensureCalendarPermission()
  if (!granted) {
    return '未获得日历权限，无法创建日程（请在弹窗中允许）'
  }

  try {
    const cal: calendarManager.Calendar = await getCalendar()
    const reminder: number[] = [startMs - 10 * 60000]
    let event: calendarManager.Event
    if (desc.length > 0) {
      event = {
        type: calendarManager.EventType.NORMAL,
        title: title,
        description: desc,
        startTime: startMs,
        endTime: startMs + durationMin * 60000,
        reminderTime: reminder
      }
    } else {
      event = {
        type: calendarManager.EventType.NORMAL,
        title: title,
        startTime: startMs,
        endTime: startMs + durationMin * 60000,
        reminderTime: reminder
      }
    }
    const eventId: number = await cal.addEvent(event)
    Logger.info('CalendarTools', 'created event ' + title + ' id=' + eventId)
    return '已创建日历日程: ' + title + '（' + formatEventTime(startMs) + ' 开始，持续 ' + durationMin + ' 分钟，已设置提前 10 分钟提醒）'
  } catch (e) {
    return '创建日程失败: ' + (e as Error).message
  }
}

async function calendarQuery(input: Record<string, Object>): Promise<string> {
  const days: number = parseInt(String(input['days'] === undefined ? '7' : input['days'])) || 7
  const granted: boolean = await ensureCalendarPermission()
  if (!granted) {
    return '未获得日历权限，无法查询日程'
  }
  try {
    const cal: calendarManager.Calendar = await getCalendar()
    const now: number = Date.now()
    const filter: calendarManager.EventFilter = calendarManager.EventFilter.filterByTime(now, now + days * 86400000)
    const events: calendarManager.Event[] = await cal.getEvents(filter)
    if (!events || events.length === 0) {
      return '未来 ' + days + ' 天内没有日程安排'
    }
    let out: string = '未来 ' + days + ' 天共 ' + events.length + ' 个日程:\n'
    for (let i: number = 0; i < events.length && i < 20; i++) {
      const ev: calendarManager.Event = events[i]
      out += '  ' + (i + 1) + '. ' + formatEventTime(ev.startTime) + ' ' + (ev.title || '未命名日程') + '\n'
    }
    return out
  } catch (e) {
    return '查询日程失败: ' + (e as Error).message
  }
}

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
    },
    '日历与时间'
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
    },
    '日历与时间'
  )

  registry.registerTool(
    'get_weekday',
    'Get the current day of the week',
    SCHEMA_WEEKDAY,
    async (_input: Record<string, Object>): Promise<string> => {
      const now: Date = new Date()
      return '今天是' + WEEKDAYS[now.getDay()]
    },
    '日历与时间'
  )

  registry.registerTool(
    'calendar_create',
    'Create a system calendar event with reminder. Use for meetings/appointments/schedules. For absolute times (下午3点/明天) compute start_time epoch ms from get_current_time first; for relative times use minutes_from_now.',
    SCHEMA_CREATE,
    calendarCreate,
    '日历与时间'
  )

  registry.registerTool(
    'calendar_query',
    'Query upcoming calendar events (next N days, default 7). Use when the user asks what is on their schedule.',
    SCHEMA_QUERY,
    calendarQuery,
    '日历与时间'
  )

  Logger.info('CalendarTools', 'Registered 5 calendar tools')
}
