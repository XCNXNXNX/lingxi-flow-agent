// ReminderTools - scheduled reminders via ReminderAgentKit (system-level, fires on time)
// ReminderAgentKit reminders fire at the scheduled time even if the app is backgrounded/killed.
// Fallback: in-app setTimeout + NotificationKit when ReminderAgent is unavailable.
import reminderAgentManager from '@ohos.reminderAgentManager'
import { notificationManager } from '@kit.NotificationKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'

interface ReminderItem {
  id: number
  title: string
  startTime: number
  description: string
}

let gReminders: ReminderItem[] = []

export function initReminderTools(): void {
  gReminders = []
}

export function getReminders(): ReminderItem[] {
  return gReminders.slice(0)
}

const SCHEMA_CREATE_REMINDER: Record<string, Object> = JSON.parse('{"type":"object","properties":{"title":{"type":"string","description":"Reminder title, e.g. 睡觉"},"description":{"type":"string","description":"Reminder description"},"minutes":{"type":"number","description":"Delay in minutes before the reminder fires. Required when the user says something like remind me in X minutes. Convert the user requested time into minutes first (use get_current_time to compute the difference for absolute times)."}},"required":["title"]}') as Record<string, Object>

const SCHEMA_LIST_REMINDERS: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>

const SCHEMA_CANCEL_REMINDER: Record<string, Object> = JSON.parse('{"type":"object","properties":{"title":{"type":"string","description":"Title of reminder to cancel"}},"required":["title"]}') as Record<string, Object>

async function trySendNotification(title: string, description: string): Promise<void> {
  try {
    const enabled: boolean = await notificationManager.isNotificationEnabled()
    if (!enabled) {
      await notificationManager.requestEnableNotification()
      const recheck: boolean = await notificationManager.isNotificationEnabled()
      if (!recheck) {
        Logger.info('ReminderTools', 'User declined notification permission')
        return
      }
    }

    const notificationRequest: notificationManager.NotificationRequest = {
      id: Date.now(),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: description
        }
      }
    }
    await notificationManager.publish(notificationRequest)
    Logger.info('ReminderTools', 'Notification sent: ' + title)
  } catch (e) {
    Logger.warn('ReminderTools', 'Notification failed: ' + (e as Error).message)
  }
}

// Publish a system-level countdown reminder via ReminderAgentKit.
// Returns the reminderId. Throws if ReminderAgent is unavailable.
async function publishSystemReminder(title: string, desc: string, minutes: number): Promise<number> {
  const agent: reminderAgentManager.WantAgent = {
    pkgName: 'com.lingxiflow.app',
    abilityName: 'EntryAbility'
  }

  const seconds: number = Math.max(1, Math.round(minutes * 60))
  const timer: reminderAgentManager.ReminderRequestTimer = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
    triggerTimeInSeconds: seconds,
    title: title,
    content: desc.length > 0 ? desc : title,
    expiredContent: '提醒已过期',
    snoozeTimes: 0,
    wantAgent: agent
  }

  const reminderId: number = await reminderAgentManager.publishReminder(timer)
  return reminderId
}

export function registerReminderTools(registry: ToolRegistry): void {
  registry.registerTool(
    'create_reminder',
    'Create a scheduled reminder. The system will show a notification at the scheduled time (countdown of minutes).',
    SCHEMA_CREATE_REMINDER,
    async (input: Record<string, Object>): Promise<string> => {
      const title: string = (input['title'] as string) || '灵犀提醒'
      const desc: string = (input['description'] as string) || ''
      const rawMinutes: string = String(input['minutes'] === undefined ? '' : input['minutes'])
      let minutes: number = parseInt(rawMinutes) || 60
      if (minutes < 1) {
        minutes = 1
      }
      const fireAt: number = Date.now() + minutes * 60000

      // 1) System-level reminder (fires on time, works in background)
      try {
        const reminderId: number = await publishSystemReminder(title, desc, minutes)
        gReminders.push({ id: reminderId, title: title, startTime: fireAt, description: desc })
        Logger.info('ReminderTools', 'scheduled via ReminderAgent: ' + title + ' in ' + minutes + 'min')
        return '已创建提醒: ' + title + '（' + minutes + ' 分钟后提醒你）'
      } catch (e) {
        Logger.warn('ReminderTools', 'ReminderAgent failed, use in-app fallback: ' + (e as Error).message)
      }

      // 2) Fallback: in-app timer (app must stay alive)
      const item: ReminderItem = { id: Date.now(), title: title, startTime: fireAt, description: desc }
      gReminders.push(item)
      setTimeout((): void => {
        trySendNotification(title, desc.length > 0 ? desc : title)
        const filtered: ReminderItem[] = []
        for (let i: number = 0; i < gReminders.length; i++) {
          if (gReminders[i].id !== item.id) {
            filtered.push(gReminders[i])
          }
        }
        gReminders = filtered
      }, minutes * 60000)
      return '已创建提醒: ' + title + '（' + minutes + ' 分钟后提醒你）'
    }
  )

  registry.registerTool(
    'list_reminders',
    'List all active reminders with their scheduled fire times',
    SCHEMA_LIST_REMINDERS,
    async (_input: Record<string, Object>): Promise<string> => {
      if (gReminders.length === 0) {
        return '没有提醒'
      }
      let out: string = '共 ' + gReminders.length + ' 个提醒:\n'
      for (let i: number = 0; i < gReminders.length; i++) {
        const r: ReminderItem = gReminders[i]
        const d: Date = new Date(r.startTime)
        out += '  ' + (i + 1) + '. ' + r.title + '（' +
          d.getHours().toString().padStart(2, '0') + ':' +
          d.getMinutes().toString().padStart(2, '0') + ' 触发）\n'
      }
      return out
    }
  )

  registry.registerTool(
    'cancel_reminder',
    'Cancel a reminder by title',
    SCHEMA_CANCEL_REMINDER,
    async (input: Record<string, Object>): Promise<string> => {
      const title: string = (input['title'] as string) || ''
      let removed: boolean = false
      for (let i: number = 0; i < gReminders.length; i++) {
        if (gReminders[i].title === title) {
          try {
            await reminderAgentManager.cancelReminder(gReminders[i].id)
          } catch (_e) {
            Logger.warn('ReminderTools', 'cancelReminder failed: ' + (_e as Error).message)
          }
          removed = true
        }
      }
      const filtered: ReminderItem[] = []
      for (let j: number = 0; j < gReminders.length; j++) {
        if (gReminders[j].title !== title) {
          filtered.push(gReminders[j])
        }
      }
      gReminders = filtered
      if (!removed) {
        return '未找到提醒: ' + title
      }
      return '已取消提醒: ' + title
    }
  )

  Logger.info('ReminderTools', 'Registered 3 reminder tools')
}
