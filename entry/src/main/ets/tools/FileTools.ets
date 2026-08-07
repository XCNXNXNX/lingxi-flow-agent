// FileTools - File operation tools for the agent
// Schema definitions use JSON.parse to avoid untyped object literal errors
import { fileIo } from '@kit.CoreFileKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'

let gBaseDir: string = ''

export function initFileTools(baseDir: string): void {
  gBaseDir = baseDir
}

export function getFileBaseDir(): string {
  return gBaseDir
}

function resolvePath(path: string): string {
  const normalized: string = path.replace(/\.\.\//g, '').replace(/\.\./g, '')
  if (normalized.startsWith('/')) {
    return gBaseDir + normalized
  }
  return gBaseDir + '/' + normalized
}

const SCHEMA_MKDIR: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"Directory path to create"}},"required":["path"]}') as Record<string, Object>

const SCHEMA_WRITE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"File path to write"},"content":{"type":"string","description":"Content to write"}},"required":["path","content"]}') as Record<string, Object>

const SCHEMA_READ: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"FILE path to read. Only files, NOT directories. Use list_files for directories."}},"required":["path"]}') as Record<string, Object>

const SCHEMA_LIST: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"DIRECTORY path to list its contents. Only directories, NOT files. Entries are marked [folder] for directories and [file] for files."}},"required":[]}') as Record<string, Object>

const SCHEMA_DELETE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"File path to delete"}},"required":["path"]}') as Record<string, Object>

const SCHEMA_SEARCH: Record<string, Object> = JSON.parse('{"type":"object","properties":{"query":{"type":"string","description":"Search keyword"}},"required":["query"]}') as Record<string, Object>

const SCHEMA_PASTE: Record<string, Object> = JSON.parse('{"type":"object","properties":{"path":{"type":"string","description":"Destination path to paste to"}},"required":["path"]}') as Record<string, Object>

export function registerFileTools(registry: ToolRegistry): void {
  registry.registerTool(
    'mkdir',
    'Create a new directory in the app sandbox',
    SCHEMA_MKDIR,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || 'new_folder'
      const full: string = resolvePath(path)
      await fileIo.mkdir(full, true)
      return '已创建文件夹: ' + path
    },
    '文件管理'
  )

  registry.registerTool(
    'write_file',
    'Write content to a file. Creates parent directories if needed.',
    SCHEMA_WRITE,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || 'note.txt'
      const content: string = input['content'] as string || ''
      const full: string = resolvePath(path)

      const lastSlash: number = full.lastIndexOf('/')
      if (lastSlash > 0) {
        try {
          fileIo.mkdirSync(full.substring(0, lastSlash), true)
        } catch (_e) {
          // directory may already exist
        }
      }

      const file: fileIo.File = fileIo.openSync(full,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)

      return '已写入 ' + content.length + ' 字符到: ' + path
    },
    '文件管理'
  )

  registry.registerTool(
    'read_file',
    'Read the text content of a FILE (not a directory). If the path is a directory it fails - use list_files to see directory contents instead.',
    SCHEMA_READ,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || ''
      const full: string = resolvePath(path)
      try {
        // Guard: reading a directory is a guaranteed failure - tell the model clearly
        const stat: fileIo.Stat = fileIo.statSync(full)
        if (stat.isDirectory()) {
          return '错误: "' + path + '" 是一个目录（文件夹）。read_file 只能读取文件。如需查看目录内容，请改用 list_files 工具列出该目录。'
        }
        const content: string = fileIo.readTextSync(full)
        return content
      } catch (e) {
        return '读取文件失败: ' + path + ' - ' + (e as Error).message
      }
    },
    '文件管理'
  )

  registry.registerTool(
    'list_files',
    'List the CONTENTS of a DIRECTORY (folder). Every entry is marked with [目录] for folders and [文件] for files, so you can pick the right tool next: use read_file only on [文件] entries, list_files only on [目录] entries.',
    SCHEMA_LIST,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || ''
      const full: string = resolvePath(path)
      try {
        // Guard: listing a file is a guaranteed failure - tell the model clearly
        const stat: fileIo.Stat = fileIo.statSync(full)
        if (!stat.isDirectory()) {
          return '错误: "' + path + '" 是一个文件而不是目录。list_files 只能列出目录内容。若要读取该文件内容，请改用 read_file 工具。'
        }
        const files: string[] = fileIo.listFileSync(full)
        if (files.length === 0) {
          return '目录为空: ' + (path || '/')
        }
        let result: string = '目录 ' + (path || '/') + ' 中有 ' + files.length + ' 项（[目录]为文件夹，[文件]为文件）:\n'
        const maxShow: number = Math.min(files.length, 30)
        for (let i: number = 0; i < maxShow; i++) {
          const child: string = files[i]
          let typeMark: string = '[文件]'
          try {
            const childStat: fileIo.Stat = fileIo.statSync(full + '/' + child)
            if (childStat.isDirectory()) {
              typeMark = '[目录]'
            }
          } catch (_e) {
            // ignore stat errors
          }
          let sizeInfo: string = ''
          if (typeMark === '[文件]') {
            try {
              sizeInfo = ' (' + fileIo.statSync(full + '/' + child).size + 'B)'
            } catch (_e) {
              // ignore
            }
          }
          result += '  ' + (i + 1) + '. ' + typeMark + ' ' + child + sizeInfo + '\n'
        }
        if (files.length > 30) {
          result += '  ...(共' + files.length + '项)'
        }
        return result
      } catch (e) {
        return '列目录失败: ' + path + ' - ' + (e as Error).message
      }
    },
    '文件管理'
  )

  registry.registerTool(
    'delete_file',
    'Delete a file from the app sandbox',
    SCHEMA_DELETE,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || ''
      const full: string = resolvePath(path)
      await fileIo.unlink(full)
      return '已删除: ' + path
    },
    '文件管理'
  )

  registry.registerTool(
    'search_files',
    'Search files by name keyword in the app sandbox',
    SCHEMA_SEARCH,
    async (input: Record<string, Object>): Promise<string> => {
      const query: string = ((input['query'] as string) || '').toLowerCase()
      const results: string[] = []
      try {
        const files: string[] = fileIo.listFileSync(gBaseDir)
        for (let i: number = 0; i < files.length; i++) {
          if (files[i].toLowerCase().indexOf(query) >= 0) {
            results.push(files[i])
          }
        }
      } catch (e) {
        return '搜索失败: ' + (e as Error).message
      }
      if (results.length === 0) {
        return '未找到匹配 "' + query + '" 的文件'
      }
      let out: string = '找到 ' + results.length + ' 个匹配（[目录]为文件夹，[文件]为文件）:\n'
      const maxShow: number = Math.min(results.length, 20)
      for (let i: number = 0; i < maxShow; i++) {
        const child: string = results[i]
        let typeMark: string = '[文件]'
        try {
          const childStat: fileIo.Stat = fileIo.statSync(gBaseDir + '/' + child)
          if (childStat.isDirectory()) {
            typeMark = '[目录]'
          }
        } catch (_e) {
          // ignore stat errors
        }
        out += '  ' + (i + 1) + '. ' + typeMark + ' ' + child + '\n'
      }
      return out
    },
    '文件管理'
  )

  Logger.info('FileTools', 'Registered 6 file tools')

let gClipboard: string = ''

  registry.registerTool(
    'copy_file',
    'Copy a file path to clipboard (for later paste)',
    SCHEMA_DELETE,
    async (input: Record<string, Object>): Promise<string> => {
      const path: string = input['path'] as string || ''
      const full: string = resolvePath(path)
      gClipboard = full
      return '已复制到剪贴板: ' + path
    },
    '文件管理'
  )

  registry.registerTool(
    'paste_file',
    'Paste the previously copied file to a new location',
    SCHEMA_PASTE,
    async (input: Record<string, Object>): Promise<string> => {
      const dest: string = input['path'] as string || ''
      if (gClipboard.length === 0) {
        return '剪贴板为空，请先复制文件'
      }
      const destFull: string = resolvePath(dest)
      try {
        const srcFile = await fileIo.open(gClipboard, 0)
        const info = await fileIo.stat(gClipboard)
        const buf: ArrayBuffer = new ArrayBuffer(info.size > 0 ? info.size : 4096)
        await fileIo.read(srcFile.fd, buf)
        await fileIo.close(srcFile)
        const destFile = await fileIo.open(destFull, 0o102)
        await fileIo.write(destFile.fd, buf)
        await fileIo.close(destFile)
        return '已粘贴到: ' + dest
      } catch (e) {
        return '粘贴失败: ' + (e as Error).message
      }
    },
    '文件管理'
  )

  Logger.info('FileTools', 'Registered 2 more copy/paste tools')
}
