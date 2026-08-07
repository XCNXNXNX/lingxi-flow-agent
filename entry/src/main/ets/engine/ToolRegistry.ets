// ToolRegistry - Tool registration and dispatch with skill-group management
// Based on NanoClaw's ToolRegistry pattern
// v2: tools are grouped into skills; users can enable/disable any tool (persisted in SQLite kv)
import { ToolDefinition, ToolFunction, ToolResult } from '../model/Types'
import { dbService } from './DatabaseService'
import { Logger } from '../utils/Logger'

export type ToolExecutor = (input: Record<string, Object>) => Promise<string>

export interface SkillToolInfo {
  name: string
  description: string
  enabled: boolean
}

export interface SkillGroup {
  name: string
  tools: SkillToolInfo[]
}

interface RegisteredTool {
  definition: ToolDefinition
  executor: ToolExecutor
  group: string
  enabled: boolean
}

const DISABLED_TOOLS_KEY: string = 'disabled_tools'

export class ToolRegistry {
  private tools: Map<string, RegisteredTool> = new Map()

  registerTool(
    name: string,
    description: string,
    parameters: Record<string, Object>,
    executor: ToolExecutor,
    group: string = '其他工具'
  ): void {
    const fn: ToolFunction = {
      name: name,
      description: description,
      parameters: parameters
    }
    const def: ToolDefinition = {
      type: 'function',
      function: fn
    }
    const registered: RegisteredTool = {
      definition: def,
      executor: executor,
      group: group,
      enabled: true
    }
    this.tools.set(name, registered)
    Logger.info('ToolRegistry', 'Registered: ' + name + ' [' + group + ']')
  }

  // Load disabled-tool state from SQLite (called after all tools are registered)
  async loadDisabledState(): Promise<void> {
    try {
      const raw: string | null = await dbService.getKV(DISABLED_TOOLS_KEY)
      if (!raw || raw.length === 0) {
        return
      }
      const disabled: string[] = JSON.parse(raw) as string[]
      for (let i: number = 0; i < disabled.length; i++) {
        const tool: RegisteredTool | undefined = this.tools.get(disabled[i])
        if (tool) {
          tool.enabled = false
        }
      }
      Logger.info('ToolRegistry', 'disabled tools loaded: ' + disabled.length)
    } catch (_e) {
      // ignore
    }
  }

  private async saveDisabledState(): Promise<void> {
    try {
      const disabled: string[] = []
      this.tools.forEach((tool: RegisteredTool, name: string): void => {
        if (!tool.enabled) {
          disabled.push(name)
        }
      })
      await dbService.setKV(DISABLED_TOOLS_KEY, JSON.stringify(disabled))
    } catch (_e) {
      // ignore
    }
  }

  setToolEnabled(name: string, enabled: boolean): void {
    const tool: RegisteredTool | undefined = this.tools.get(name)
    if (tool) {
      tool.enabled = enabled
      this.saveDisabledState()
      Logger.info('ToolRegistry', (enabled ? 'Enabled: ' : 'Disabled: ') + name)
    }
  }

  isToolEnabled(name: string): boolean {
    const tool: RegisteredTool | undefined = this.tools.get(name)
    return tool ? tool.enabled : false
  }

  getToolDefinitions(): ToolDefinition[] {
    const defs: ToolDefinition[] = []
    this.tools.forEach((tool: RegisteredTool): void => {
      defs.push(tool.definition)
    })
    return defs
  }

  // Only enabled tools are sent to the LLM
  getEnabledToolDefinitions(): ToolDefinition[] {
    const defs: ToolDefinition[] = []
    this.tools.forEach((tool: RegisteredTool): void => {
      if (tool.enabled) {
        defs.push(tool.definition)
      }
    })
    return defs
  }

  // Skill groups for the settings page (dynamic, reflects real registry state)
  getSkillGroups(): SkillGroup[] {
    const groups: SkillGroup[] = []
    this.tools.forEach((tool: RegisteredTool, name: string): void => {
      let group: SkillGroup | undefined = undefined
      for (let i: number = 0; i < groups.length; i++) {
        if (groups[i].name === tool.group) {
          group = groups[i]
          break
        }
      }
      if (!group) {
        group = { name: tool.group, tools: [] }
        groups.push(group)
      }
      const info: SkillToolInfo = {
        name: name,
        description: tool.definition.function.description,
        enabled: tool.enabled
      }
      group.tools.push(info)
    })
    return groups
  }

  // One-line summary of enabled tools per group, for the dynamic system prompt
  getEnabledToolSummary(): string {
    const groups: SkillGroup[] = this.getSkillGroups()
    let summary: string = ''
    for (let i: number = 0; i < groups.length; i++) {
      const g: SkillGroup = groups[i]
      const names: string[] = []
      for (let j: number = 0; j < g.tools.length; j++) {
        if (g.tools[j].enabled) {
          names.push(g.tools[j].name)
        }
      }
      if (names.length > 0) {
        summary += '- ' + g.name + '：' + names.join('、') + '\n'
      }
    }
    return summary.trim()
  }

  getToolCount(): number {
    return this.tools.size
  }

  getEnabledToolCount(): number {
    let count: number = 0
    this.tools.forEach((tool: RegisteredTool): void => {
      if (tool.enabled) {
        count++
      }
    })
    return count
  }

  hasTool(name: string): boolean {
    return this.tools.has(name)
  }

  async executeTool(name: string, inputJson: string, toolCallId: string): Promise<ToolResult> {
    const tool: RegisteredTool | undefined = this.tools.get(name)
    if (!tool) {
      Logger.warn('ToolRegistry', 'Unknown tool: ' + name)
      const errResult: ToolResult = {
        toolCallId: toolCallId,
        content: 'Error: unknown tool "' + name + '"',
        isError: true
      }
      return errResult
    }
    if (!tool.enabled) {
      Logger.warn('ToolRegistry', 'Disabled tool called: ' + name)
      const errResult: ToolResult = {
        toolCallId: toolCallId,
        content: 'Error: tool "' + name + '" 已被禁用，请先在设置中启用该技能',
        isError: true
      }
      return errResult
    }

    try {
      const input: Record<string, Object> = JSON.parse(inputJson) as Record<string, Object>
      Logger.info('ToolRegistry', 'Execute: ' + name)
      const resultStr: string = await tool.executor(input)
      const okResult: ToolResult = {
        toolCallId: toolCallId,
        content: resultStr,
        isError: false
      }
      return okResult
    } catch (e) {
      const errorMsg: string = (e as Error).message || String(e)
      Logger.error('ToolRegistry', name + ' failed: ' + errorMsg)
      const failResult: ToolResult = {
        toolCallId: toolCallId,
        content: 'Error: ' + errorMsg,
        isError: true
      }
      return failResult
    }
  }
}
