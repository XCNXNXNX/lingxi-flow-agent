// ConfigService - API configuration via preferences
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { ApiConfig } from '../model/Types'
import { Logger } from '../utils/Logger'

const PREF_NAME = 'lingxi_config'
const KEY_API_KEY = 'api_key'
const KEY_BASE_URL = 'base_url'
const KEY_MODEL = 'model'
const KEY_MAX_TOKENS = 'max_tokens'
const KEY_TEMPERATURE = 'temperature'

const DEFAULT_BASE_URL = 'https://api.deepseek.com/v1'
const DEFAULT_MODEL = 'deepseek-chat'
const DEFAULT_MAX_TOKENS =8192
const DEFAULT_TEMPERATURE =0.7

export class ConfigService {
 private pref: preferences.Preferences | null = null

  async init(context: common.UIAbilityContext): Promise<void> {
  this.pref = await preferences.getPreferences(context, PREF_NAME)
  Logger.info('ConfigService', 'initialized')
  }

  async getApiConfig(): Promise<ApiConfig> {
 const key: string = await this.getApiKey()
 const baseUrl: string = await this.getBaseUrl()
 const model: string = await this.getModel()
 const maxTokens: number = await this.getMaxTokens()
 const temperature: number = await this.getTemperature()
 const config: ApiConfig = {
 apiKey: key,
 baseUrl: baseUrl,
 model: model,
 maxTokens: maxTokens,
 temperature: temperature
 }
 return config
 }

 async saveApiConfig(config: ApiConfig): Promise<void> {
 await this.saveApiKey(config.apiKey)
 await this.setBaseUrl(config.baseUrl)
 await this.setModel(config.model)
 await this.pref!.put(KEY_MAX_TOKENS, config.maxTokens)
 await this.pref!.put(KEY_TEMPERATURE, config.temperature)
 await this.pref!.flush()
 }

 async saveApiKey(key: string): Promise<void> {
 await this.pref!.put(KEY_API_KEY, key)
 await this.pref!.flush()
 }

 async getApiKey(): Promise<string> {
 return await this.pref!.get(KEY_API_KEY, '') as string
 }

 async getBaseUrl(): Promise<string> {
 return await this.pref!.get(KEY_BASE_URL, DEFAULT_BASE_URL) as string
 }

 async setBaseUrl(url: string): Promise<void> {
 await this.pref!.put(KEY_BASE_URL, url)
 await this.pref!.flush()
 }

 async getModel(): Promise<string> {
 return await this.pref!.get(KEY_MODEL, DEFAULT_MODEL) as string
 }

 async setModel(model: string): Promise<void> {
 await this.pref!.put(KEY_MODEL, model)
 await this.pref!.flush()
 }

 async getMaxTokens(): Promise<number> {
 return await this.pref!.get(KEY_MAX_TOKENS, DEFAULT_MAX_TOKENS) as number
 }

 async getTemperature(): Promise<number> {
 return await this.pref!.get(KEY_TEMPERATURE, DEFAULT_TEMPERATURE) as number
 }

  async hasApiKey(): Promise<boolean> {
  const key = await this.getApiKey()
  return key.length >0
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
