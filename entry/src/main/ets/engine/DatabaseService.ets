// DatabaseService - SQLite persistence via relationalStore
// Ported from NanoClaw db.ts, enhanced for Lingxi Flow
import { relationalStore } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'
import { ChatMessage, ChatConversation, ScheduledTask, TaskRunLog, ToolCallRecord } from '../model/Types'

const DB_NAME: string = 'lingxi_flow.db'
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S1
}

const CREATE_SCHEMA: string = `
  CREATE TABLE IF NOT EXISTS chats (
    id TEXT PRIMARY KEY,
    name TEXT,
    last_message_time TEXT,
    last_message_preview TEXT
  );

  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    chat_id TEXT,
    sender TEXT,
    sender_name TEXT,
    content TEXT,
    timestamp TEXT,
    is_from_me INTEGER,
    tool_calls TEXT,
    FOREIGN KEY (chat_id) REFERENCES chats(id)
  );
  CREATE INDEX IF NOT EXISTS idx_msg_timestamp ON messages(timestamp);
  CREATE INDEX IF NOT EXISTS idx_msg_chat ON messages(chat_id);

  CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id TEXT PRIMARY KEY,
    chat_id TEXT NOT NULL,
    prompt TEXT NOT NULL,
    schedule_type TEXT NOT NULL,
    schedule_value TEXT NOT NULL,
    next_run TEXT,
    last_run TEXT,
    last_result TEXT,
    status TEXT DEFAULT 'active',
    created_at TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_task_next_run ON scheduled_tasks(next_run);
  CREATE INDEX IF NOT EXISTS idx_task_status ON scheduled_tasks(status);

  CREATE TABLE IF NOT EXISTS task_run_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    run_at TEXT NOT NULL,
    duration_ms INTEGER NOT NULL,
    status TEXT NOT NULL,
    result TEXT,
    error TEXT,
    FOREIGN KEY (task_id) REFERENCES scheduled_tasks(id)
  );

  CREATE TABLE IF NOT EXISTS kv_store (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
`

export class DatabaseService {
  private rdbStore: relationalStore.RdbStore | null = null

  async init(context: common.UIAbilityContext): Promise<void> {
    this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG)
    const statements: string[] = CREATE_SCHEMA.split(';').filter((s: string): boolean => s.trim().length > 0)
    for (let i: number = 0; i < statements.length; i++) {
      await this.rdbStore.executeSql(statements[i].trim())
    }
    Logger.info('DatabaseService', 'initialized')
  }

  // --- Chat operations ---

  async ensureChat(chatId: string, name: string): Promise<void> {
    const now: string = new Date().toISOString()
    await this.rdbStore!.executeSql(
      'INSERT OR IGNORE INTO chats (id, name, last_message_time, last_message_preview) VALUES (?, ?, ?, ?)',
      [chatId, name, now, '']
    )
  }

  async updateChatPreview(chatId: string, preview: string): Promise<void> {
    const now: string = new Date().toISOString()
    await this.rdbStore!.executeSql(
      'UPDATE chats SET last_message_time = ?, last_message_preview = ? WHERE id = ?',
      [now, preview.substring(0, 100), chatId]
    )
  }

  async getAllChats(): Promise<ChatConversation[]> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      'SELECT id, name, last_message_time, last_message_preview FROM chats ORDER BY last_message_time DESC'
    )
    const chats: ChatConversation[] = []
    while (resultSet.goToNextRow()) {
      const conv: ChatConversation = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        lastMessageTime: resultSet.getString(resultSet.getColumnIndex('last_message_time')),
        lastMessagePreview: resultSet.getString(resultSet.getColumnIndex('last_message_preview'))
      }
      chats.push(conv)
    }
    resultSet.close()
    return chats
  }

  // --- Message operations ---

  async storeMessage(msg: ChatMessage): Promise<void> {
    const toolCallsJson: string | null = msg.toolCalls ? JSON.stringify(msg.toolCalls) : null
    await this.rdbStore!.executeSql(
      'INSERT OR REPLACE INTO messages (id, chat_id, sender, sender_name, content, timestamp, is_from_me, tool_calls) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [msg.id, msg.chatId, msg.sender, msg.senderName, msg.content, msg.timestamp, msg.isFromMe ? 1 : 0, toolCallsJson]
    )
    await this.updateChatPreview(msg.chatId, msg.content)
  }

  async getMessages(chatId: string, limit: number = 50): Promise<ChatMessage[]> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      'SELECT * FROM ( SELECT id, chat_id, sender, sender_name, content, timestamp, is_from_me, tool_calls FROM messages WHERE chat_id = ? ORDER BY timestamp DESC LIMIT ? ) ORDER BY timestamp',
      [chatId, limit]
    )
    const messages: ChatMessage[] = []
    while (resultSet.goToNextRow()) {
      const toolCallsStr: string = resultSet.getString(resultSet.getColumnIndex('tool_calls'))
      let toolCalls: ToolCallRecord[] | undefined = undefined
      if (toolCallsStr && toolCallsStr !== 'null' && toolCallsStr.length > 0) {
        try {
          toolCalls = JSON.parse(toolCallsStr) as ToolCallRecord[]
        } catch (_e) {
          // ignore parse error
        }
      }
      const msg: ChatMessage = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        chatId: resultSet.getString(resultSet.getColumnIndex('chat_id')),
        sender: resultSet.getString(resultSet.getColumnIndex('sender')),
        senderName: resultSet.getString(resultSet.getColumnIndex('sender_name')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        timestamp: resultSet.getString(resultSet.getColumnIndex('timestamp')),
        isFromMe: resultSet.getLong(resultSet.getColumnIndex('is_from_me')) === 1,
        toolCalls: toolCalls
      }
      messages.push(msg)
    }
    resultSet.close()
    return messages
  }

  async deleteChat(chatId: string): Promise<void> {
    await this.rdbStore!.executeSql('DELETE FROM messages WHERE chat_id = ?', [chatId])
    await this.rdbStore!.executeSql('DELETE FROM chats WHERE id = ?', [chatId])
  }

  async renameChat(chatId: string, name: string): Promise<void> {
    await this.rdbStore!.executeSql(
      'UPDATE chats SET name = ? WHERE id = ?', [name, chatId]
    )
  }

  async deleteMessage(msgId: string): Promise<void> {
    await this.rdbStore!.executeSql('DELETE FROM messages WHERE id = ?', [msgId])
  }

  async getFirstUserMessage(chatId: string): Promise<string | null> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      "SELECT content FROM messages WHERE chat_id = ? AND is_from_me = 1 ORDER BY timestamp ASC LIMIT 1",
      [chatId]
    )
    let content: string | null = null
    if (resultSet.goToNextRow()) {
      content = resultSet.getString(0)
    }
    resultSet.close()
    return content
  }

  // --- Scheduled task operations ---

  async createTask(task: ScheduledTask): Promise<void> {
    await this.rdbStore!.executeSql(
      'INSERT INTO scheduled_tasks (id, chat_id, prompt, schedule_type, schedule_value, next_run, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [task.id, task.chatId, task.prompt, task.scheduleType, task.scheduleValue, task.nextRun, task.status, task.createdAt]
    )
  }

  async getTaskById(id: string): Promise<ScheduledTask | null> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      'SELECT * FROM scheduled_tasks WHERE id = ?', [id]
    )
    let task: ScheduledTask | null = null
    if (resultSet.goToNextRow()) {
      task = this.readTask(resultSet)
    }
    resultSet.close()
    return task
  }

  async getAllTasks(): Promise<ScheduledTask[]> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      'SELECT * FROM scheduled_tasks ORDER BY created_at DESC'
    )
    const tasks: ScheduledTask[] = []
    while (resultSet.goToNextRow()) {
      tasks.push(this.readTask(resultSet))
    }
    resultSet.close()
    return tasks
  }

  async getDueTasks(): Promise<ScheduledTask[]> {
    const now: string = new Date().toISOString()
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      "SELECT * FROM scheduled_tasks WHERE status = 'active' AND next_run IS NOT NULL AND next_run <= ? ORDER BY next_run",
      [now]
    )
    const tasks: ScheduledTask[] = []
    while (resultSet.goToNextRow()) {
      tasks.push(this.readTask(resultSet))
    }
    resultSet.close()
    return tasks
  }

  async updateTaskStatus(id: string, status: string): Promise<void> {
    await this.rdbStore!.executeSql(
      'UPDATE scheduled_tasks SET status = ? WHERE id = ?', [status, id]
    )
  }

  async updateTaskAfterRun(id: string, nextRun: string | null, lastResult: string): Promise<void> {
    const now: string = new Date().toISOString()
    const newStatus: string = nextRun === null ? 'completed' : 'active'
    await this.rdbStore!.executeSql(
      'UPDATE scheduled_tasks SET next_run = ?, last_run = ?, last_result = ?, status = ? WHERE id = ?',
      [nextRun, now, lastResult, newStatus, id]
    )
  }

  async deleteTask(id: string): Promise<void> {
    await this.rdbStore!.executeSql('DELETE FROM task_run_logs WHERE task_id = ?', [id])
    await this.rdbStore!.executeSql('DELETE FROM scheduled_tasks WHERE id = ?', [id])
  }

  async logTaskRun(log: TaskRunLog): Promise<void> {
    await this.rdbStore!.executeSql(
      'INSERT INTO task_run_logs (task_id, run_at, duration_ms, status, result, error) VALUES (?, ?, ?, ?, ?, ?)',
      [log.taskId, log.runAt, log.durationMs, log.status, log.result, log.error]
    )
  }

  // --- KV Store ---

  async getKV(key: string): Promise<string | null> {
    const resultSet: relationalStore.ResultSet = await this.rdbStore!.querySql(
      'SELECT value FROM kv_store WHERE key = ?', [key]
    )
    let value: string | null = null
    if (resultSet.goToNextRow()) {
      value = resultSet.getString(0)
    }
    resultSet.close()
    return value
  }

  async setKV(key: string, value: string): Promise<void> {
    await this.rdbStore!.executeSql(
      'INSERT OR REPLACE INTO kv_store (key, value) VALUES (?, ?)', [key, value]
    )
  }

  // --- Helpers ---

  private readTask(resultSet: relationalStore.ResultSet): ScheduledTask {
    const idIdx: number = resultSet.getColumnIndex('id')
    const chatIdIdx: number = resultSet.getColumnIndex('chat_id')
    const promptIdx: number = resultSet.getColumnIndex('prompt')
    const sTypeIdx: number = resultSet.getColumnIndex('schedule_type')
    const sValIdx: number = resultSet.getColumnIndex('schedule_value')
    const nextRunIdx: number = resultSet.getColumnIndex('next_run')
    const lastRunIdx: number = resultSet.getColumnIndex('last_run')
    const lastResultIdx: number = resultSet.getColumnIndex('last_result')
    const statusIdx: number = resultSet.getColumnIndex('status')
    const createdAtIdx: number = resultSet.getColumnIndex('created_at')

    return {
      id: resultSet.getString(idIdx),
      chatId: resultSet.getString(chatIdIdx),
      prompt: resultSet.getString(promptIdx),
      scheduleType: resultSet.getString(sTypeIdx) as ('cron' | 'interval' | 'once'),
      scheduleValue: resultSet.getString(sValIdx),
      nextRun: resultSet.isColumnNull(nextRunIdx) ? null : resultSet.getString(nextRunIdx),
      lastRun: resultSet.isColumnNull(lastRunIdx) ? null : resultSet.getString(lastRunIdx),
      lastResult: resultSet.isColumnNull(lastResultIdx) ? null : resultSet.getString(lastResultIdx),
      status: resultSet.getString(statusIdx) as ('active' | 'paused' | 'completed'),
      createdAt: resultSet.getString(createdAtIdx)
    }
  }
}

export const dbService: DatabaseService = new DatabaseService()
