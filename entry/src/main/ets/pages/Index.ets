import { router } from '@kit.ArkUI'
import { ThemeStyle, ThemeColors, getThemeColors } from '../utils/ThemeService'

class Particle {
  x: number = 0
  y: number = 0
  speed: number = 0.3
  size: number = 4
  opacity: number = 0.15
  wobble: number = 0
  wobbleSpeed: number = 0
  wobbleAmp: number = 0
}

@Entry
@Component
struct Index {
  @StorageLink('themeStyle') currentTheme: ThemeStyle = 'lingxi'
  @State activeTab: number = 0
  @State titleVisible: boolean = true
  @State flowText: string = ''
  @State showSplash: boolean = true
  @State particles: Particle[] = []
  @State iconScale: number = 1
  @State tabPressed: number = -1
  private flowIndex: number = 0
  private flowTimer: number = -1
  private snowTimer: number = -1
  private breatheTimer: number = -1
  private destroyed: boolean = false

  aboutToAppear(): void {
    this.destroyed = false
    this.initParticles()
    this.startBreathe()
    setTimeout(() => { if (!this.destroyed) { this.showSplash = false } }, 400)
    setTimeout(() => { if (!this.destroyed) { this.startFlowType() } }, 600)
    // 小艺意图唤起（foreground 模式先进 Index）→ 跳转对话页消费预设
    const preset: string | undefined = AppStorage.get<string>('intentPresetText')
    if (preset && preset.length > 0) {
      router.pushUrl({ url: 'pages/ChatPage' })
    }
  }

  aboutToDisappear(): void {
    this.destroyed = true
    if (this.flowTimer >= 0) { clearInterval(this.flowTimer) }
    if (this.snowTimer >= 0) { clearInterval(this.snowTimer) }
    if (this.breatheTimer >= 0) { clearInterval(this.breatheTimer) }
  }

  initParticles(): void {
    const list: Particle[] = []
    for (let i: number = 0; i < 20; i++) {
      const p: Particle = new Particle()
      p.x = Math.random() * 100
      p.y = Math.random() * -90 - 10
      p.speed = 0.12 + Math.random() * 0.45
      p.size = 2 + Math.random() * 5
      p.opacity = 0.06 + Math.random() * 0.18
      p.wobble = Math.random() * Math.PI * 2
      p.wobbleSpeed = 0.006 + Math.random() * 0.02
      p.wobbleAmp = 0.2 + Math.random() * 0.9
      list.push(p)
    }
    this.particles = list
    this.snowTimer = setInterval(() => {
      for (let j: number = 0; j < this.particles.length; j++) {
        const p: Particle = this.particles[j]
        p.wobble += p.wobbleSpeed
        p.x += Math.sin(p.wobble) * p.wobbleAmp
        p.y += p.speed
        p.opacity += (Math.sin(p.wobble * 2.3) * 0.008)
        if (p.opacity > 0.28) { p.opacity = 0.28 }
        if (p.opacity < 0.04) { p.opacity = 0.04 }
        if (p.y > 112) {
          p.y = -12
          p.x = Math.random() * 100
        }
      }
      this.particles = [...this.particles]
    }, 50)
  }

  startFlowType(): void {
    const full: string = '_flow'
    this.flowIndex = 0
    this.flowTimer = setInterval(() => {
      if (this.flowIndex < full.length) {
        this.flowText += full.charAt(this.flowIndex)
        this.flowIndex++
      } else {
        clearInterval(this.flowTimer)
        this.flowTimer = -1
      }
    }, 120)
  }

  startBreathe(): void {
    this.breatheTimer = setInterval(() => {
      animateTo({ duration: 3000, curve: Curve.EaseInOut }, () => {
        this.iconScale = this.iconScale > 1.02 ? 0.98 : 1.03
      })
    }, 3000)
  }

  col(): ThemeColors { return getThemeColors(this.currentTheme) }

  build() {
    Stack() {
      // Main content
      Column() {
        // Header area with icon and title
        Column() {
          Column().height(48)

          Image($r('app.media.icon_app'))
            .width(64).height(64)
            .borderRadius(16)
            .scale({ x: this.iconScale, y: this.iconScale })
            .opacity(this.showSplash ? 0 : 1)
            .animation({ duration: 400, curve: Curve.EaseOut })

          Row() {
            Text('Lingxi')
              .fontSize(30)
              .fontColor(this.col().textPrimary)
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
              .letterSpacing(2)

            Text(this.flowText)
              .fontSize(30)
              .fontColor(this.col().textOnPrimary)
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
              .letterSpacing(2)
          }
          .margin({ top: 16 })
          .opacity(this.showSplash ? 0 : 1)
          .animation({ duration: 300, curve: Curve.EaseOut })
        }
        .width('100%')
        .padding({ top: 48, bottom: 16 })
        .backgroundColor('transparent')

        // Empty middle space for snow
        Column()
          .width('100%')
          .layoutWeight(1)

        // Bottom tabs
        Row() {
          this.tab('对话', 0)
          this.tab('任务', 1)
          this.tab('设置', 2)
          this.tab('文件', 3)
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .backgroundColor(this.col().glassNav)
        .backdropBlur(10)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('transparent')

      // Background gradient
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.col().gradientEnd, 0],
            [this.col().accent, 0.35],
            [this.col().bg, 0.7],
            [this.col().bg, 1]
          ]
        })
        .zIndex(-2)

      // Background image with theme filter
      Image($r('app.media.bg_home'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(0.10)
        .zIndex(-1)

      // Snow particles
      ForEach(this.particles, (p: Particle) => {
        Circle()
          .width(p.size)
          .height(p.size)
          .fill(this.col().accent)
          .opacity(p.opacity)
          .position({ x: p.x + '%', y: p.y + '%' })
      })

      // Splash screen
      if (this.showSplash) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.col().bg)
          .animation({ duration: 300, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tab(label: string, idx: number) {
    Column() {
      Text(label)
        .fontSize($r('app.float.font_size_small'))
        .fontColor(this.activeTab === idx ? this.col().accent : this.col().textTertiary)
        .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Normal)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .scale({ x: this.tabPressed === idx ? 0.92 : 1, y: this.tabPressed === idx ? 0.92 : 1 })
    .animation({ duration: 120, curve: Curve.EaseInOut })
    .onClick(() => {
      this.tabPressed = idx
      setTimeout(() => { this.tabPressed = -1 }, 150)
      this.activeTab = idx
      const urls: string[] = ['pages/ChatPage', 'pages/ResultPage', 'pages/SettingsPage', 'pages/FileBrowserPage']
      router.pushUrl({ url: urls[idx] })
    })
  }
}
