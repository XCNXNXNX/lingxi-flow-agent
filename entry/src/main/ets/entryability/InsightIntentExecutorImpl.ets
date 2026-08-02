// InsightIntentExecutorImpl - 小艺意图执行器
// JumpFunctionPage (ToolsDomain): 小艺触发"打开XX功能" → 预填灵犀对话并自动执行
// 意图配置见 resources/base/profile/insight_intent.json
import { InsightIntentExecutor } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import insightIntent from '@ohos.app.ability.insightIntent'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const INTENT_PRESET_KEY: string = 'intentPresetText'

export default class InsightIntentExecutorImpl extends InsightIntentExecutor {
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>,
    pageLoader: window.WindowStage): insightIntent.ExecuteResult {
    hilog.info(DOMAIN, 'InsightIntent', 'execute: %{public}s %{public}s', name, JSON.stringify(param))

    // 把意图参数翻译成灵犀的预设提示词，页面 aboutToAppear 时消费并自动执行
    let preset: string = ''
    if (name === 'JumpFunctionPage') {
      const pageId: string = (param['pageId'] as string) || ''
      if (pageId.length > 0) {
        preset = '帮我打开' + pageId
      }
    }
    if (preset.length === 0) {
      preset = '你好，小艺让我来找你帮忙'
    }
    AppStorage.setOrCreate<string>(INTENT_PRESET_KEY, preset)
    hilog.info(DOMAIN, 'InsightIntent', 'preset: %{public}s', preset)

    const res: insightIntent.ExecuteResult = { code: 0, result: {} }
    return res
  }
}
