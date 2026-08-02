// ReminderTools - Reminder tools for the agent with notification support
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

const SCHEMA_CREATE_REMINDER: Record<string, Object> = JSON.parse('{"type":"object","properties":{"title":{"type":"string","description":"Reminder title"},"description":{"type":"string","description":"Reminder description"}},"required":["title"]}') as Record<string, Object>

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

export function registerReminderTools(registry: ToolRegistry): void {
  registry.registerTool(
    'create_reminder',
    'Create a new reminder and send system notification',
    SCHEMA_CREATE_REMINDER,
    async (input: Record<string, Object>): Promise<string> => {
      const title: string = input['title'] as string || '灵犀提醒'
      const desc: string = input['description'] as string || ''
      const item: ReminderItem = {
        id: Date.now(),
        title: title,
        startTime: Date.now() + 3600000,
        description: desc
      }
      gReminders.push(item)
      Logger.info('ReminderTools', 'Created: ' + title)
      trySendNotification(title, desc)
      return '已创建提醒: ' + title + '（通知已发出）'
    }
  )

  registry.registerTool(
    'list_reminders',
    'List all active reminders',
    SCHEMA_LIST_REMINDERS,
    async (_input: Record<string, Object>): Promise<string> => {
      if (gReminders.length === 0) {
        return '没有提醒'
      }
      let out: string = '共 ' + gReminders.length + ' 个提醒:\n'
      for (let i: number = 0; i < gReminders.length; i++) {
        const r: ReminderItem = gReminders[i]
        const d: Date = new Date(r.startTime)
        out += '  ' + (i + 1) + '. ' + r.title + ' (' + d.toLocaleString() + ')\n'
      }
      return out
    }
  )

  registry.registerTool(
    'cancel_reminder',
    'Cancel a reminder by title',
    SCHEMA_CANCEL_REMINDER,
    async (input: Record<string, Object>): Promise<string> => {
      const title: string = input['title'] as string || ''
      const before: number = gReminders.length
      const filtered: ReminderItem[] = []
      for (let i: number = 0; i < gReminders.length; i++) {
        if (gReminders[i].title !== title) {
          filtered.push(gReminders[i])
        }
      }
      gReminders = filtered
      if (before === gReminders.length) {
        return '未找到提醒: ' + title
      }
      return '已取消提醒: ' + title
    }
  )

  Logger.info('ReminderTools', 'Registered 3 reminder tools')
}
