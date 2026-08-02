import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { configService } from '../services/ConfigService'
import { dbService } from '../engine/DatabaseService'
import { agentCore } from '../engine/AgentCore'
import { ragService } from '../engine/RagService'
import { taskScheduler } from '../engine/TaskScheduler'
import { distributedService } from '../services/DistributedService'
import { ThemeService } from '../utils/ThemeService'

const DOMAIN: number = 0x0000

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      await configService.init(this.context)
      await dbService.init(this.context)
      await ThemeService.init()
      const filesDir: string = this.context.filesDir
      await ragService.init(this.context, filesDir)
      ragService.buildIndexIfNeeded()
      await distributedService.init(this.context)
      await agentCore.init(this.context, filesDir)
      taskScheduler.start()
      hilog.info(DOMAIN, 'EntryAbility', 'Services initialized')
    } catch (e) {
      hilog.error(DOMAIN, 'EntryAbility', 'Init failed: %{public}s', JSON.stringify(e))
    }
  }

  onDestroy(): void {
    taskScheduler.stop()
    hilog.info(DOMAIN, 'EntryAbility', 'Ability onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'EntryAbility', 'Succeeded loading main page.')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'EntryAbility', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'EntryAbility', 'Ability onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'EntryAbility', 'Ability onBackground')
  }
}
