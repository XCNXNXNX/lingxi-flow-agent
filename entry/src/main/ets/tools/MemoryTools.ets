// MemoryTools - persistent memory/notes tools for the agent
// Notes are stored as Markdown files in the sandbox memory/ directory
// Ported from NanoClaw tools/MemoryTools.ets, adapted to Lingxi Flow conventions
import { fileIo } from '@kit.CoreFileKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { ragService } from '../engine/RagService'
import { Logger } from '../utils/Logger'

let gMemoryDir: string = ''

export function initMemoryTools(filesDir: string): void {
  gMemoryDir = filesDir + '/memory'
  try {
    fileIo.mkdirSync(gMemoryDir, true)
  } catch (_e) {
    // directory may already exist
  }
}

export function getMemoryDir(): string {
  return gMemoryDir
}

// Memory names are restricted to safe filename characters
function sanitizeName(name: string): string {
  return name.replace(/[^a-zA-Z0-9_\u4e00-\u9fa5-]/g, '_')
}

const SCHEMA_READ: Record<string, Object> = JSON.parse('{"type":"object","properties":{"name":{"type":"string","description":"Memory note name (without .md extension)"}},"required":["name"]}') as Record<string, Object>

const SCHEMA_WRITE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"name":{"type":"string","description":"Memory note name (without .md extension)"},"content":{"type":"string","description":"Markdown content to remember"}},"required":["name","content"]}') as Record<string, Object>

const SCHEMA_LIST: Record<string, Object> = JSON.parse('{"type":"object","properties":{},"required":[]}') as Record<string, Object>

async function memoryWrite(input: Record<string, Object>): Promise<string> {
  const name: string = (input['name'] as string) || ''
  const content: string = (input['content'] as string) || ''
  if (name.length === 0) {
    return 'Error: name is required'
  }
  if (content.length === 0) {
    return 'Error: content is required'
  }

  const safeName: string = sanitizeName(name)
  const path: string = gMemoryDir + '/' + safeName + '.md'
  try {
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, content)
    fileIo.closeSync(file)
    ragService.markDirty()
    return '已记住 "' + name + '"（' + content.length + ' 字符）'
  } catch (e) {
    return '保存记忆失败: ' + (e as Error).message
  }
}

async function memoryRead(input: Record<string, Object>): Promise<string> {
  const name: string = (input['name'] as string) || ''
  if (name.length === 0) {
    return 'Error: name is required'
  }
  const safeName: string = sanitizeName(name)
  const path: string = gMemoryDir + '/' + safeName + '.md'
  try {
    const content: string = fileIo.readTextSync(path)
    return content
  } catch (_e) {
    return '未找到记忆 "' + name + '"'
  }
}

async function memoryList(_input: Record<string, Object>): Promise<string> {
  try {
    const entries: string[] = fileIo.listFileSync(gMemoryDir)
    const mdFiles: string[] = []
    for (let i: number = 0; i < entries.length; i++) {
      if (entries[i].endsWith('.md')) {
        mdFiles.push(entries[i])
      }
    }
    if (mdFiles.length === 0) {
      return '还没有任何记忆'
    }
    let out: string = '共 ' + mdFiles.length + ' 条记忆:\n'
    for (let j: number = 0; j < mdFiles.length; j++) {
      const f: string = mdFiles[j]
      const name: string = f.substring(0, f.length - 3)
      try {
        const stat: fileIo.Stat = fileIo.statSync(gMemoryDir + '/' + f)
        out += '  ' + (j + 1) + '. ' + name + '（' + stat.size + ' 字符）\n'
      } catch (_e) {
        out += '  ' + (j + 1) + '. ' + name + '\n'
      }
    }
    return out
  } catch (_e) {
    return '还没有任何记忆'
  }
}

export function registerMemoryTools(registry: ToolRegistry): void {
  registry.registerTool(
    'memory_write',
    'Write or update a persistent memory note. Use this to remember important user information (preferences, facts, todo items) that should persist across conversations. Notes are Markdown files.',
    SCHEMA_WRITE,
    memoryWrite
  )

  registry.registerTool(
    'memory_read',
    'Read a persistent memory note by name. Use this when you need information the user saved earlier or across conversations.',
    SCHEMA_READ,
    memoryRead
  )

  registry.registerTool(
    'memory_list',
    'List all saved memory notes with sizes.',
    SCHEMA_LIST,
    memoryList
  )

  Logger.info('MemoryTools', 'Registered 3 memory tools')
}
