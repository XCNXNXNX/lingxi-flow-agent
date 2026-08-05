// DevicePage - 跨设备协同
// 设备发现 + 任务进度跨设备同步 + 提醒指令分发（手机输入 → 手表提醒）
import { router, promptAction } from '@kit.ArkUI'
import { distributedService, TaskStatePayload, ReminderCommand, LOCAL_DEVICE_ID } from '../services/DistributedService'
import { publishSystemReminder } from '../tools/ReminderTools'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'
import { DeviceInfo, DeviceType, DeviceConnectionStatus } from '../model/Types'

@Entry
@Component
struct DevicePage {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State devices: DeviceInfo[] = []
  @State granted: boolean = false
  @State remoteTask: TaskStatePayload | null = null
  @State reminderTitle: string = ''
  @State reminderMinutes: string = '10'
  @State sentCount: number = 0
  @State receivedCount: number = 0
  private watching: boolean = false

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  async aboutToAppear(): Promise<void> {
    await this.refresh()
  }

  async refresh(): Promise<void> {
    this.granted = await distributedService.hasPermission()
    if (this.granted) {
      await this.startWatching()
      this.devices = await distributedService.getDeviceList()
      distributedService.subscribeDeviceChange((devices: DeviceInfo[]): void => {
        this.devices = devices
      })
    }
  }

  async grantPermission(): Promise<void> {
    const ok: boolean = await distributedService.requestPermission()
    this.granted = ok
    if (ok) {
      promptAction.showToast({ message: '已授权，开始发现设备', duration: 2000 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '未授权，跨设备功能不可用', duration: 2000 })
    }
  }

  async startWatching(): Promise<void> {
    if (this.watching) {
      return
    }
    this.watching = true
    // 任务进度同步（对端设备运行任务 → 本机实时展示）
    await distributedService.watchTaskState((payload: TaskStatePayload | null): void => {
      if (payload) {
        this.remoteTask = payload
      }
    })
    // 提醒指令（对端设备分发提醒 → 本机创建系统提醒）
    await distributedService.watchReminderCommand((cmd: ReminderCommand): void => {
      this.receivedCount++
      publishSystemReminder(cmd.title, cmd.description, cmd.minutes).then((): void => {
        promptAction.showToast({ message: '收到 ' + cmd.fromDevice + ' 的提醒：' + cmd.title, duration: 3000 })
      }).catch((e: Error): void => {
        promptAction.showToast({ message: '创建提醒失败: ' + e.message, duration: 3000 })
      })
    })
  }

  async sendReminder(): Promise<void> {
    const title: string = this.reminderTitle.trim()
    const minutes: number = parseInt(this.reminderMinutes) || 10
    if (title.length === 0) {
      promptAction.showToast({ message: '请输入提醒内容', duration: 1500 })
      return
    }
    const cmd: ReminderCommand = {
      title: title,
      description: '来自手机灵犀的提醒',
      minutes: minutes,
      fromDevice: '本机',
      senderId: LOCAL_DEVICE_ID
    }
    await distributedService.publishReminderCommand(cmd)
    this.sentCount++
    this.reminderTitle = ''
    promptAction.showToast({ message: '已分发提醒到在线设备（' + minutes + ' 分钟后触发）', duration: 2500 })
  }

  deviceIcon(deviceType: DeviceType): string {
    if (deviceType === DeviceType.PHONE) { return '📱' }
    if (deviceType === DeviceType.TABLET) { return '💻' }
    if (deviceType === DeviceType.WATCH) { return '⌚' }
    if (deviceType === DeviceType.TV) { return '📺' }
    if (deviceType === DeviceType.CAR) { return '🚗' }
    return '📡'
  }

  build() {
    Column() {
      // Header
      Row() {
        Image($r('sys.symbol.arrow_left'))
          .width($r('app.float.icon_size_md')).height($r('app.float.icon_size_md'))
          .fillColor(this.col().textPrimary)
          .onClick(() => { router.back() })
        Text('跨设备')
          .fontSize($r('app.float.font_size_subtitle'))
          .fontColor(this.col().textPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.Center)
        if (!this.granted) {
          Button('授权')
            .fontSize($r('app.float.font_size_caption'))
            .fontColor('#FFFFFF')
            .backgroundColor(this.col().accent)
            .borderRadius($r('app.float.radius_sm'))
            .height(30)
            .onClick(() => { this.grantPermission() })
        }
      }
      .width('100%').padding($r('app.float.spacing_md'))
      .backgroundColor(this.col().glassNav).backdropBlur(10)

      Scroll() {
        Column() {
          if (!this.granted) {
            // 未授权引导
            Column() {
              Image($r('app.media.icon_device_1'))
                .width(96).height(96)
                .objectFit(ImageFit.Contain)
                .opacity(0.85)
              Text('开启跨设备协同')
                .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                .fontWeight(FontWeight.Medium).margin({ top: $r('app.float.spacing_sm') })
              Text('需要授权分布式组网权限，用于发现附近设备并同步任务状态')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .textAlign(TextAlign.Center).margin({ top: $r('app.float.spacing_xs') })
              Button('立即授权')
                .fontSize($r('app.float.font_size_body')).fontColor('#FFFFFF')
                .backgroundColor(this.col().accent).borderRadius($r('app.float.radius_md'))
                .height(40).margin({ top: $r('app.float.spacing_md') })
                .onClick(() => { this.grantPermission() })
            }
            .width('100%').alignItems(HorizontalAlign.Center)
            .padding($r('app.float.spacing_xl'))
            .backgroundColor(this.col().glassCard)
            .borderRadius($r('app.float.radius_lg'))
            .border({ width: 1, color: this.col().divider })
          } else {
            // 设备列表
            Row() {
              Text('附近设备')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .fontWeight(FontWeight.Bold)
              Blank()
              Image($r('app.media.icon_device_2'))
                .width(22).height(22)
                .objectFit(ImageFit.Contain)
                .opacity(0.7)
            }
            .width('100%').margin({ bottom: $r('app.float.spacing_sm') })

            if (this.devices.length === 0) {
              Column() {
                Image($r('app.media.icon_device_1'))
                  .width(72).height(72)
                  .objectFit(ImageFit.Contain)
                  .opacity(0.5)
                Text('未发现设备')
                  .fontSize($r('app.float.font_size_body')).fontColor(this.col().textTertiary)
                  .margin({ top: $r('app.float.spacing_sm') })
                Text('确保两台设备登录同一华为账号、开启蓝牙/WLAN 并互相靠近')
                  .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                  .textAlign(TextAlign.Center).margin({ top: $r('app.float.spacing_xs') })
              }
              .width('100%').alignItems(HorizontalAlign.Center)
              .padding($r('app.float.spacing_xl'))
              .backgroundColor(this.col().surface)
              .borderRadius($r('app.float.radius_lg'))
              .border({ width: 1, color: this.col().divider })
            } else {
              ForEach(this.devices, (dev: DeviceInfo) => {
                Row() {
                  Text(this.deviceIcon(dev.deviceType)).fontSize(22).margin({ right: $r('app.float.spacing_sm') })
                  Column() {
                    Text(dev.deviceName)
                      .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                    Text(dev.getTypeText() + ' · ' + dev.getStatusText())
                      .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Circle()
                    .width(10).height(10)
                    .fill(dev.status === DeviceConnectionStatus.CONNECTED ? '#10B981' : this.col().textTertiary)
                }
                .width('100%')
                .padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .borderRadius($r('app.float.radius_md'))
                .border({ width: 1, color: this.col().divider })
                .margin({ bottom: $r('app.float.spacing_sm') })
              })
            }

            // 对端任务状态
            Text('任务同步')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              .fontWeight(FontWeight.Bold)
              .width('100%').margin({ top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

            if (this.remoteTask) {
              Column() {
                Row() {
                  Text('🤖').fontSize(18).margin({ right: $r('app.float.spacing_sm') })
                  Text('其他设备正在执行任务')
                    .fontSize($r('app.float.font_size_body')).fontColor(this.col().textPrimary)
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  Text(this.remoteTask.stepIndex + '/' + this.remoteTask.stepCount + ' 步')
                    .fontSize($r('app.float.font_size_caption')).fontColor(this.col().accent)
                }
                .width('100%')
                Text(this.remoteTask.goal)
                  .fontSize($r('app.float.font_size_small')).fontColor(this.col().textSecondary)
                  .width('100%').margin({ top: 6 })
                Text('当前：' + this.remoteTask.currentStep)
                  .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                  .width('100%').margin({ top: 4 })
              }
              .width('100%').alignItems(HorizontalAlign.Start)
              .padding($r('app.float.spacing_md'))
              .backgroundColor(this.col().glassCard)
              .borderRadius($r('app.float.radius_lg'))
              .border({ width: 1, color: this.col().divider })
            } else {
              Text('未收到其他设备的任务进度（任务页执行任务时自动同步）')
                .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
                .width('100%')
                .padding($r('app.float.spacing_md'))
                .backgroundColor(this.col().surface)
                .borderRadius($r('app.float.radius_md'))
            }

            // 提醒分发
            Text('提醒分发（手机 → 其他设备）')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              .fontWeight(FontWeight.Bold)
              .width('100%').margin({ top: $r('app.float.spacing_md'), bottom: $r('app.float.spacing_sm') })

            Row() {
              TextInput({ text: this.reminderTitle, placeholder: '提醒内容，如：喝水' })
                .layoutWeight(1).height(40)
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant)
                .borderRadius($r('app.float.radius_sm'))
                .padding({ left: 12, right: 12 })
                .onChange((v: string): void => { this.reminderTitle = v })
              TextInput({ text: this.reminderMinutes, placeholder: '分钟' })
                .width(64).height(40)
                .fontColor(this.col().textPrimary).placeholderColor(this.col().textTertiary)
                .backgroundColor(this.col().surfaceVariant)
                .borderRadius($r('app.float.radius_sm'))
                .type(InputType.Number)
                .margin({ left: 8 })
                .onChange((v: string): void => { this.reminderMinutes = v })
              Button('分发')
                .fontSize($r('app.float.font_size_caption')).fontColor('#FFFFFF')
                .backgroundColor(this.col().accent)
                .borderRadius($r('app.float.radius_sm'))
                .height(40).margin({ left: 8 })
                .onClick(() => { this.sendReminder() })
            }
            .width('100%')

            Text('已分发 ' + this.sentCount + ' 次 · 收到 ' + this.receivedCount + ' 条跨设备提醒')
              .fontSize($r('app.float.font_size_caption')).fontColor(this.col().textTertiary)
              .width('100%').margin({ top: $r('app.float.spacing_sm') })
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding($r('app.float.spacing_md'))
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(this.col().bg)
    }
    .width('100%').height('100%').backgroundColor(this.col().bg)
  }
}
