// ToolRegistry - Tool registration and dispatch
// Based on NanoClaw's ToolRegistry pattern
import { ToolDefinition, ToolFunction, ToolResult } from '../model/Types'
import { Logger } from '../utils/Logger'

export type ToolExecutor = (input: Record<string, Object>) => Promise<string>

interface RegisteredTool {
  definition: ToolDefinition
  executor: ToolExecutor
}

export class ToolRegistry {
  private tools: Map<string, RegisteredTool> = new Map()

  registerTool(
    name: string,
    description: string,
    parameters: Record<string, Object>,
    executor: ToolExecutor
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
      executor: executor
    }
    this.tools.set(name, registered)
    Logger.info('ToolRegistry', 'Registered: ' + name)
  }

  getToolDefinitions(): ToolDefinition[] {
    const defs: ToolDefinition[] = []
    this.tools.forEach((tool: RegisteredTool): void => {
      defs.push(tool.definition)
    })
    return defs
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
