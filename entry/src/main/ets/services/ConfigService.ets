// ConfigService - API configuration via preferences
// v2: API library (multiple saved profiles, quick switch) + provider presets
// Backward compatible: getApiKey/getBaseUrl/getModel/... read from the active profile
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { ApiConfig, ApiProfile, ProviderPreset } from '../model/Types'
import { Logger } from '../utils/Logger'

const PREF_NAME = 'lingxi_config'
const KEY_API_KEY = 'api_key'
const KEY_BASE_URL = 'base_url'
const KEY_MODEL = 'model'
const KEY_MAX_TOKENS = 'max_tokens'
const KEY_TEMPERATURE = 'temperature'
const KEY_EMBED_KEY = 'embedding_key'
const KEY_EMBED_URL = 'embedding_url'
const KEY_MCP_URL = 'mcp_url'
const KEY_SYSTEM_PROMPT = 'system_prompt'
const KEY_API_PROFILES = 'api_profiles'
const KEY_ACTIVE_PROFILE = 'active_api_profile'

const DEFAULT_BASE_URL = 'https://api.deepseek.com/v1'
const DEFAULT_MODEL = 'deepseek-chat'
const DEFAULT_MAX_TOKENS = 8192
const DEFAULT_TEMPERATURE = 0.7
const DEFAULT_EMBED_URL = 'https://api.siliconflow.cn/v1/embeddings'

// One-tap provider presets: users don't need to fill base URLs manually
export const PROVIDER_PRESETS: ProviderPreset[] = [
  { name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', note: '国内直连 · 性价比高' },
  { name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', note: '需网络代理' },
  { name: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo', note: '阿里云 · 国内直连' },
  { name: 'Kimi', baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k', note: '月之暗面 · 国内直连' },
  { name: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash', note: '国内直连 · 有免费档' },
  { name: 'SiliconFlow', baseUrl: 'https://api.siliconflow.cn/v1', model: 'deepseek-ai/DeepSeek-V3', note: '硅基流动 · 聚合多模型' },
  { name: '百度千帆', baseUrl: 'https://qianfan.baidubce.com/v2', model: 'ernie-4.0-turbo-8k', note: '国内直连' },
  { name: '腾讯混元', baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1', model: 'hunyuan-lite', note: '国内直连 · 有免费档' },
  { name: '火山方舟', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', model: 'doubao-1-5-pro-32k-250115', note: '豆包 · 需在控制台建推理接入点' },
  { name: 'Ollama 本地', baseUrl: 'http://127.0.0.1:11434/v1', model: 'qwen2.5:7b', note: '本地模型 · 免费离线' }
]

export class ConfigService {
  private pref: preferences.Preferences | null = null
  private profiles: ApiProfile[] = []
  private activeProfileId: string = ''
  private profilesLoaded: boolean = false

  async init(context: common.UIAbilityContext): Promise<void> {
    this.pref = await preferences.getPreferences(context, PREF_NAME)
    await this.loadProfiles()
    Logger.info('ConfigService', 'initialized with ' + this.profiles.length + ' profile(s)')
  }

  // --- API library ---

  private async loadProfiles(): Promise<void> {
    const raw: string = await this.pref!.get(KEY_API_PROFILES, '') as string
    if (raw.length === 0) {
      // First run (or upgrade): migrate legacy flat keys into a default profile
      await this.migrateLegacyConfig()
      return
    }
    this.profiles = this.parseProfiles(raw)
    this.activeProfileId = await this.pref!.get(KEY_ACTIVE_PROFILE, '') as string
    // Fallback: if stored active id is invalid, use first profile
    if (this.activeProfileId.length === 0 || this.findProfile(this.activeProfileId) === null) {
      if (this.profiles.length > 0) {
        this.activeProfileId = this.profiles[0].id
      }
    }
    this.profilesLoaded = true
  }

  private async migrateLegacyConfig(): Promise<void> {
    const legacyKey: string = await this.pref!.get(KEY_API_KEY, '') as string
    const legacyBase: string = await this.pref!.get(KEY_BASE_URL, '') as string
    const legacyModel: string = await this.pref!.get(KEY_MODEL, '') as string
    const legacyMax: number = await this.pref!.get(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS) as number
    const legacyTemp: number = await this.pref!.get(KEY_TEMPERATURE, DEFAULT_TEMPERATURE) as number
    const legacyEmbedKey: string = await this.pref!.get(KEY_EMBED_KEY, '') as string
    const legacyEmbedUrl: string = await this.pref!.get(KEY_EMBED_URL, '') as string

    if (legacyKey.length > 0 || legacyBase.length > 0) {
      const profile: ApiProfile = {
        id: 'default',
        name: '默认配置',
        provider: '自定义',
        baseUrl: legacyBase.length > 0 ? legacyBase : DEFAULT_BASE_URL,
        apiKey: legacyKey,
        model: legacyModel.length > 0 ? legacyModel : DEFAULT_MODEL,
        maxTokens: legacyMax,
        temperature: legacyTemp,
        embedKey: legacyEmbedKey,
        embedUrl: legacyEmbedUrl
      }
      this.profiles = [profile]
      this.activeProfileId = 'default'
      await this.persistProfiles()
      Logger.info('ConfigService', 'migrated legacy config to profile: default')
    } else {
      this.profiles = []
      this.activeProfileId = ''
    }
    this.profilesLoaded = true
  }

  private parseProfiles(raw: string): ApiProfile[] {
    const list: ApiProfile[] = []
    try {
      const arr: Record<string, Object>[] = JSON.parse(raw) as Record<string, Object>[]
      for (let i: number = 0; i < arr.length; i++) {
        const o: Record<string, Object> = arr[i]
        list.push({
          id: (o['id'] as string) || 'p_' + i,
          name: (o['name'] as string) || '未命名配置',
          provider: (o['provider'] as string) || '自定义',
          baseUrl: (o['baseUrl'] as string) || DEFAULT_BASE_URL,
          apiKey: (o['apiKey'] as string) || '',
          model: (o['model'] as string) || DEFAULT_MODEL,
          maxTokens: (o['maxTokens'] as number) || DEFAULT_MAX_TOKENS,
          temperature: (o['temperature'] as number) || DEFAULT_TEMPERATURE,
          embedKey: (o['embedKey'] as string) || '',
          embedUrl: (o['embedUrl'] as string) || ''
        })
      }
    } catch (e) {
      Logger.warn('ConfigService', 'parse profiles failed: ' + (e as Error).message)
    }
    return list
  }

  private async persistProfiles(): Promise<void> {
    await this.pref!.put(KEY_API_PROFILES, JSON.stringify(this.profiles))
    await this.pref!.put(KEY_ACTIVE_PROFILE, this.activeProfileId)
    await this.pref!.flush()
  }

  getProfiles(): ApiProfile[] {
    return this.profiles.slice(0)
  }

  async getActiveProfile(): Promise<ApiProfile | null> {
    if (!this.profilesLoaded) {
      await this.loadProfiles()
    }
    return this.findProfile(this.activeProfileId)
  }

  private findProfile(id: string): ApiProfile | null {
    for (let i: number = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === id) {
        return this.profiles[i]
      }
    }
    return null
  }

  // Upsert a profile (new id => add, existing id => update)
  async saveProfile(profile: ApiProfile): Promise<void> {
    if (!this.profilesLoaded) {
      await this.loadProfiles()
    }
    const idx: number = this.profiles.findIndex((p: ApiProfile): boolean => p.id === profile.id)
    if (idx >= 0) {
      this.profiles[idx] = profile
    } else {
      this.profiles.push(profile)
    }
    // Saving a profile activates it (quick switch UX)
    this.activeProfileId = profile.id
    await this.persistProfiles()
  }

  async deleteProfile(id: string): Promise<void> {
    const idx: number = this.profiles.findIndex((p: ApiProfile): boolean => p.id === id)
    if (idx < 0) {
      return
    }
    this.profiles.splice(idx, 1)
    if (this.activeProfileId === id) {
      this.activeProfileId = this.profiles.length > 0 ? this.profiles[0].id : ''
    }
    await this.persistProfiles()
  }

  async setActiveProfileId(id: string): Promise<void> {
    if (this.findProfile(id) === null) {
      return
    }
    this.activeProfileId = id
    await this.persistProfiles()
  }

  // --- Backward-compatible readers (from active profile) ---

  async getApiConfig(): Promise<ApiConfig> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    const config: ApiConfig = {
      apiKey: profile ? profile.apiKey : '',
      baseUrl: profile ? profile.baseUrl : DEFAULT_BASE_URL,
      model: profile ? profile.model : DEFAULT_MODEL,
      maxTokens: profile ? profile.maxTokens : DEFAULT_MAX_TOKENS,
      temperature: profile ? profile.temperature : DEFAULT_TEMPERATURE
    }
    return config
  }

  async saveApiConfig(config: ApiConfig): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    const target: ApiProfile = profile ? profile : this.newProfile()
    target.apiKey = config.apiKey
    target.baseUrl = config.baseUrl
    target.model = config.model
    target.maxTokens = config.maxTokens
    target.temperature = config.temperature
    await this.saveProfile(target)
  }

  private newProfile(): ApiProfile {
    return {
      id: 'p_' + Date.now(),
      name: '默认配置',
      provider: '自定义',
      baseUrl: DEFAULT_BASE_URL,
      apiKey: '',
      model: DEFAULT_MODEL,
      maxTokens: DEFAULT_MAX_TOKENS,
      temperature: DEFAULT_TEMPERATURE,
      embedKey: '',
      embedUrl: ''
    }
  }

  async saveApiKey(key: string): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile) {
      profile.apiKey = key
      await this.saveProfile(profile)
    }
  }

  async getApiKey(): Promise<string> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.apiKey : ''
  }

  async getBaseUrl(): Promise<string> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.baseUrl : DEFAULT_BASE_URL
  }

  async setBaseUrl(url: string): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile) {
      profile.baseUrl = url
      await this.saveProfile(profile)
    }
  }

  async getModel(): Promise<string> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.model : DEFAULT_MODEL
  }

  async setModel(model: string): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile) {
      profile.model = model
      await this.saveProfile(profile)
    }
  }

  async getMaxTokens(): Promise<number> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.maxTokens : DEFAULT_MAX_TOKENS
  }

  async getTemperature(): Promise<number> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.temperature : DEFAULT_TEMPERATURE
  }

  // --- Embedding (RAG) config (per profile, fallback to SiliconFlow) ---

  async getEmbeddingKey(): Promise<string> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    return profile ? profile.embedKey : ''
  }

  async saveEmbeddingKey(key: string): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile) {
      profile.embedKey = key
      await this.saveProfile(profile)
    }
  }

  async getEmbeddingUrl(): Promise<string> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile && profile.embedUrl.length > 0) {
      return profile.embedUrl
    }
    // Default: SiliconFlow BGE-M3 (reachable from China, unlike OpenAI)
    return DEFAULT_EMBED_URL
  }

  async saveEmbeddingUrl(url: string): Promise<void> {
    const profile: ApiProfile | null = await this.getActiveProfile()
    if (profile) {
      profile.embedUrl = url
      await this.saveProfile(profile)
    }
  }

  // --- MCP server config (global, not per profile) ---

  async getMcpUrl(): Promise<string> {
    return await this.pref!.get(KEY_MCP_URL, '') as string
  }

  async saveMcpUrl(url: string): Promise<void> {
    await this.pref!.put(KEY_MCP_URL, url)
    await this.pref!.flush()
  }

  // --- Custom system prompt (user persona) ---

  async getSystemPrompt(): Promise<string> {
    return await this.pref!.get(KEY_SYSTEM_PROMPT, '') as string
  }

  async saveSystemPrompt(prompt: string): Promise<void> {
    await this.pref!.put(KEY_SYSTEM_PROMPT, prompt)
    await this.pref!.flush()
  }

  async hasApiKey(): Promise<boolean> {
    const key = await this.getApiKey()
    return key.length > 0
  }

  async getKV(key: string): Promise<string | null> {
    return await this.pref!.get(key, '') as string || null
  }

  async setKV(key: string, value: string): Promise<void> {
    await this.pref!.put(key, value)
    await this.pref!.flush()
  }

  async deleteKV(key: string): Promise<void> {
    await this.pref!.delete(key)
    await this.pref!.flush()
  }
}

export const configService = new ConfigService()
