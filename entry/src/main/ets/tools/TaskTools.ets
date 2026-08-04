// TaskTools - scheduled task management (wires up TaskScheduler)
// task_create / task_list / task_cancel operate on the scheduled_tasks table;
// TaskScheduler polls every 60s and runs due tasks through AgentCore.
import { ToolRegistry } from '../engine/ToolRegistry'
import { dbService } from '../engine/DatabaseService'
import { generateId } from '../utils/TextFormatter'
import { Logger } from '../utils/Logger'
import { ScheduledTask } from '../model/Types'

const SCHEMA_CREATE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"prompt":{"type":"string","description":"What the AI should do when this task runs, e.g. 提醒我喝水"},"schedule_type":{"type":"string","enum":["once","interval"],"description":"once = run one time soon; interval = repeat every N minutes"},"interval_minutes":{"type":"number","description":"Minutes between runs when schedule_type=interval (default 60)"}},"required":["prompt","schedule_type"]}') as Record<string, Object>

const SCHEMA_LIST: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>

const SCHEMA_CANCEL: Record<string, Object> = JSON.parse('{"type":"object","properties":{"task_id":{"type":"string","description":"Task id to cancel (from task_list)"}},"required":["task_id"]}') as Record<string, Object>

async function taskCreate(input: Record<string, Object>): Promise<string> {
  const prompt: string = (input['prompt'] as string) || ''
  if (prompt.length === 0) {
    return 'Error: prompt is required'
  }
  const st: string = (input['schedule_type'] as string) || 'once'
  const intervalMin: number = parseInt(String(input['interval_minutes'] === undefined ? '60' : input['interval_minutes'])) || 60
  const now: string = new Date().toISOString()
  let nextRun: string
  let scheduleValue: string = 'now'
  if (st === 'interval') {
    nextRun = new Date(Date.now() + intervalMin * 60000).toISOString()
    scheduleValue = String(intervalMin)
  } else {
    // once: due immediately, the scheduler picks it up on the next 60s poll
    nextRun = now
  }
  const task: ScheduledTask = {
    id: 'task_' + generateId(),
    chatId: 'task_' + generateId(),
    prompt: prompt,
    scheduleType: st === 'interval' ? 'interval' : 'once',
    scheduleValue: scheduleValue,
    nextRun: nextRun,
    lastRun: null,
    lastResult: null,
    status: 'active',
    createdAt: now
  }
  try {
    await dbService.createTask(task)
    Logger.info('TaskTools', 'created task ' + task.id + ' type=' + st)
    if (st === 'interval') {
      return '已创建周期任务: ' + prompt + '（每 ' + intervalMin + ' 分钟执行一次）'
    }
    return '已创建一次性任务: ' + prompt + '（将在 1 分钟内执行）'
  } catch (e) {
    return '创建任务失败: ' + (e as Error).message
  }
}

async function taskList(_input: Record<string, Object>): Promise<string> {
  try {
    const tasks: ScheduledTask[] = await dbService.getAllTasks()
    const active: ScheduledTask[] = []
    for (let i: number = 0; i < tasks.length; i++) {
      if (tasks[i].status === 'active') {
        active.push(tasks[i])
      }
    }
    if (active.length === 0) {
      return '没有进行中的定时任务'
    }
    let out: string = '共 ' + active.length + ' 个定时任务:\n'
    for (let j: number = 0; j < active.length; j++) {
      const t: ScheduledTask = active[j]
      const type: string = t.scheduleType === 'interval' ? '每 ' + t.scheduleValue + ' 分钟' : '一次性'
      out += '  ' + (j + 1) + '. [' + t.id.substring(0, 8) + '] ' + t.prompt + '（' + type + '）\n'
    }
    return out
  } catch (e) {
    return '查询任务失败: ' + (e as Error).message
  }
}

async function taskCancel(input: Record<string, Object>): Promise<string> {
  const taskId: string = ((input['task_id'] as string) || '').trim()
  if (taskId.length === 0) {
    return 'Error: task_id is required'
  }
  try {
    const tasks: ScheduledTask[] = await dbService.getAllTasks()
    for (let i: number = 0; i < tasks.length; i++) {
      if (tasks[i].id === taskId || tasks[i].id.startsWith(taskId)) {
        await dbService.deleteTask(tasks[i].id)
        return '已取消定时任务: ' + tasks[i].prompt
      }
    }
    return '未找到任务: ' + taskId
  } catch (e) {
    return '取消任务失败: ' + (e as Error).message
  }
}

export function registerTaskTools(registry: ToolRegistry): void {
  registry.registerTool(
    'task_create',
    'Create a scheduled AI task. Use when the user wants something done repeatedly (every X minutes, e.g. 每30分钟提醒我喝水) or once in the background. The task runs through the AI agent automatically.',
    SCHEMA_CREATE,
    taskCreate
  )

  registry.registerTool(
    'task_list',
    'List all active scheduled tasks with their ids and intervals.',
    SCHEMA_LIST,
    taskList
  )

  registry.registerTool(
    'task_cancel',
    'Cancel a scheduled task by id (prefix accepted, from task_list).',
    SCHEMA_CANCEL,
    taskCancel
  )

  Logger.info('TaskTools', 'Registered 3 task tools')
}
