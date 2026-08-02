// ThemeService - Theme management with AppStorage
import { configService } from '../services/ConfigService'

export type ThemeStyle = 'lobster' | 'lingxi'

const THEME_KEY: string = 'theme_style'

export class ThemeColors {
  bg: string = '#0e1015'
  bgElevated: string = '#161920'
  bgHover: string = '#1f2330'
  surface: string = '#161920'
  surfaceVariant: string = '#1f2330'
  textPrimary: string = '#f0f0f2'
  textSecondary: string = '#8b8fa3'
  textTertiary: string = '#6b7094'
  textOnPrimary: string = '#FFFFFF'
  accent: string = '#bd4531'
  accentLight: string = '#e05a45'
  divider: string = '#2a2d3a'
  glassNav: string = 'rgba(14,16,21,0.85)'
  glassCard: string = 'rgba(255,255,255,0.06)'
  glassInput: string = 'rgba(255,255,255,0.08)'
  glassOverlay: string = 'rgba(22,25,32,0.88)'
  gradientStart: string = '#bd4531'
  gradientEnd: string = '#e05a45'
  badgeBg: string = 'rgba(189,69,49,0.1)'
  tabBlock: string = 'rgba(255,255,255,0.04)'
}

class LingxiColors extends ThemeColors {
  bg: string = '#F8F9FE'
  bgElevated: string = '#FFFFFF'
  bgHover: string = '#EEF0F8'
  surface: string = '#FFFFFF'
  surfaceVariant: string = '#EEF0F8'
  textPrimary: string = '#1E293B'
  textSecondary: string = '#64748B'
  textTertiary: string = '#94A3B8'
  textOnPrimary: string = '#FFFFFF'
  accent: string = '#4F46E5'
  accentLight: string = '#818CF8'
  divider: string = '#E2E8F0'
  glassNav: string = 'rgba(248,249,254,0.85)'
  glassCard: string = 'rgba(255,255,255,0.65)'
  glassInput: string = 'rgba(255,255,255,0.75)'
  glassOverlay: string = 'rgba(255,255,255,0.92)'
  gradientStart: string = '#4F46E5'
  gradientEnd: string = '#7C3AED'
  badgeBg: string = 'rgba(79,70,229,0.1)'
  tabBlock: string = 'rgba(255,255,255,0.5)'
}

export function getThemeColors(style: ThemeStyle | undefined): ThemeColors {
  if (style === 'lingxi') {
    return new LingxiColors()
  }
  return new ThemeColors()
}

export class ThemeService {
  private static currentStyle: ThemeStyle = 'lingxi'

  static async init(): Promise<void> {
    const saved: string | null = await configService.getKV('theme_style')
    if (saved === 'lingxi' || saved === 'lobster') {
      ThemeService.currentStyle = saved
    }
    AppStorage.setOrCreate<string>('themeStyle', ThemeService.currentStyle)
  }

  static getStyle(): ThemeStyle {
    return ThemeService.currentStyle
  }

  static async setStyle(style: ThemeStyle): Promise<void> {
    ThemeService.currentStyle = style
    AppStorage.set<string>('themeStyle', style)
    await configService.setKV('theme_style', style)
  }

  static getColors(): ThemeColors {
    return getThemeColors(ThemeService.currentStyle)
  }
}
