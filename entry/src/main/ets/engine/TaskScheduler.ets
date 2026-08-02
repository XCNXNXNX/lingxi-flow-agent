// TaskScheduler - Simplified polling scheduler
// Polls DB every 60s for due tasks, runs them through AgentCore
import { Logger } from '../utils/Logger'
import { dbService } from './DatabaseService'
import { agentCore } from './AgentCore'
import { ScheduledTask } from '../model/Types'

const SCHEDULER_POLL_INTERVAL: number = 60000

export class TaskScheduler {
  private running: boolean = false
  private timerId: number = -1

  start(): void {
    if (this.running) {
      return
    }
    this.running = true
    Logger.info('TaskScheduler', 'started')
    this.poll()
  }

  stop(): void {
    this.running = false
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    Logger.info('TaskScheduler', 'stopped')
  }

  private async poll(): Promise<void> {
    if (!this.running) {
      return
    }

    try {
      const dueTasks: ScheduledTask[] = await dbService.getDueTasks()
      if (dueTasks.length > 0) {
        Logger.info('TaskScheduler', 'due tasks: ' + dueTasks.length)
      }

      for (let i: number = 0; i < dueTasks.length; i++) {
        await this.runTask(dueTasks[i])
      }
    } catch (e) {
      Logger.error('TaskScheduler', 'poll error: ' + (e as Error).message)
    }

    if (this.running) {
      this.timerId = setTimeout((): void => {
        this.poll()
      }, SCHEDULER_POLL_INTERVAL)
    }
  }

  private async runTask(task: ScheduledTask): Promise<void> {
    const startTime: number = Date.now()
    Logger.info('TaskScheduler', 'running task: ' + task.id)

    let result: string | null = null
    let error: string | null = null

    try {
      await agentCore.runAgent(task.prompt, task.chatId, (event): void => {
        if (event.type === 'text') {
          result = event.content
        } else if (event.type === 'error') {
          error = event.error
        }
      })
    } catch (e) {
      error = (e as Error).message
      Logger.error('TaskScheduler', 'task ' + task.id + ' failed: ' + error)
    }

    const durationMs: number = Date.now() - startTime

    await dbService.logTaskRun({
      taskId: task.id,
      runAt: new Date().toISOString(),
      durationMs: durationMs,
      status: error ? 'error' : 'success',
      result: result,
      error: error
    })

    const nextRun: string | null = this.computeNextRun(task.scheduleType, task.scheduleValue)
    const resultStr: string = result !== null ? result : ''
    const resultSummary: string = error ? 'Error: ' + error : (resultStr ? resultStr.substring(0, 200) : 'Completed')
    await dbService.updateTaskAfterRun(task.id, nextRun, resultSummary)

    Logger.info('TaskScheduler', 'task ' + task.id + ' completed in ' + durationMs + 'ms')
  }

  private computeNextRun(scheduleType: string, scheduleValue: string): string | null {
    const now: Date = new Date()

    if (scheduleType === 'once') {
      return null
    }

    if (scheduleType === 'interval') {
      const minutes: number = parseInt(scheduleValue) || 60
      const next: Date = new Date(now.getTime() + minutes * 60000)
      return next.toISOString()
    }

    return null
  }
}

export const taskScheduler: TaskScheduler = new TaskScheduler()
