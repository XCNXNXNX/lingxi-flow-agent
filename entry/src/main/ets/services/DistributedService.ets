// DistributedService - 跨设备协同服务
// 设备发现: @kit.DistributedServiceKit distributedDeviceManager
// 状态同步: @ohos.data.distributedKVStore 分布式键值库（同华为账号 + 组网设备间自动同步）
// 能力: 发现附近设备 / 任务进度实时同步 / 提醒指令跨设备分发（手机输入 → 手表提醒）
import { distributedDeviceManager } from '@kit.DistributedServiceKit'
import distributedKVStore from '@ohos.data.distributedKVStore'
import { abilityAccessCtrl, bundleManager, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'
import { DeviceInfo, DeviceType, DeviceConnectionStatus } from '../model/Types'

const STORE_ID: string = 'lingxi_flow_sync'
const KEY_TASK_STATE: string = 'task_state'
const KEY_REMINDER_CMD: string = 'reminder_cmd'

interface KvManagerConfigInfo {
  bundleName: string
  context: common.Context
}

interface DeviceStateChangePayload {
  action: distributedDeviceManager.DeviceStateChange
  device: distributedDeviceManager.DeviceBasicInfo
}

export interface TaskStatePayload {
  goal: string
  stepIndex: number
  stepCount: number
  currentStep: string
  status: string
  updatedAt: string
}

export interface ReminderCommand {
  title: string
  description: string
  minutes: number
  fromDevice: string
}

function mapDeviceType(type: string): DeviceType {
  const t: string = type.toLowerCase()
  if (t.indexOf('phone') >= 0) {
    return DeviceType.PHONE
  }
  if (t.indexOf('tablet') >= 0) {
    return DeviceType.TABLET
  }
  if (t.indexOf('watch') >= 0 || t.indexOf('wearable') >= 0) {
    return DeviceType.WATCH
  }
  if (t.indexOf('tv') >= 0) {
    return DeviceType.TV
  }
  if (t.indexOf('car') >= 0) {
    return DeviceType.CAR
  }
  return DeviceType.UNKNOWN
}

export class DistributedService {
  private kvStore: distributedKVStore.DeviceKVStore | null = null
  private dm: distributedDeviceManager.DeviceManager | null = null
  private context: common.UIAbilityContext | null = null
  private initialized: boolean = false
  private deviceListener: ((devices: DeviceInfo[]) => void) | null = null

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    this.context = context
    try {
      this.dm = distributedDeviceManager.createDeviceManager(context.applicationInfo.name)
      this.initialized = true
      Logger.info('DistributedService', 'deviceManager ready')
    } catch (e) {
      Logger.warn('DistributedService', 'deviceManager init failed: ' + (e as Error).message)
    }
  }

  // DISTRIBUTED_DATASYNC is user_grant - request at runtime
  async requestPermission(): Promise<boolean> {
    if (!this.context) {
      return false
    }
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const res: PermissionRequestResult = await atManager.requestPermissionsFromUser(
        this.context, ['ohos.permission.DISTRIBUTED_DATASYNC'] as Permissions[])
      if (res.authResults && res.authResults.length > 0) {
        return res.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      }
      return false
    } catch (e) {
      Logger.warn('DistributedService', 'permission request failed: ' + (e as Error).message)
      return false
    }
  }

  async hasPermission(): Promise<boolean> {
    if (!this.context) {
      return false
    }
    try {
      const bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      const tokenId: number = bundleInfo.appInfo.accessTokenId
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const status: abilityAccessCtrl.GrantStatus = await atManager.checkAccessToken(
        tokenId, 'ohos.permission.DISTRIBUTED_DATASYNC' as Permissions)
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    } catch (e) {
      return false
    }
  }

  // --- Device discovery ---

  async getDeviceList(): Promise<DeviceInfo[]> {
    if (!this.dm) {
      return []
    }
    try {
      const list: distributedDeviceManager.DeviceBasicInfo[] = await this.dm.getAvailableDeviceList()
      const devices: DeviceInfo[] = []
      for (let i: number = 0; i < list.length; i++) {
        const info: distributedDeviceManager.DeviceBasicInfo = list[i]
        const d: DeviceInfo = new DeviceInfo(info.deviceId, info.deviceName, mapDeviceType(info.deviceType))
        d.status = DeviceConnectionStatus.CONNECTED
        devices.push(d)
      }
      return devices
    } catch (e) {
      Logger.warn('DistributedService', 'getDeviceList failed: ' + (e as Error).message)
      return []
    }
  }

  subscribeDeviceChange(listener: (devices: DeviceInfo[]) => void): void {
    this.deviceListener = listener
    if (!this.dm) {
      return
    }
    try {
      this.dm.on('deviceStateChange', (data: DeviceStateChangePayload): void => {
        if (this.deviceListener) {
          this.deviceListener([])
          // refresh list async
          this.getDeviceList().then((devices: DeviceInfo[]): void => {
            if (this.deviceListener) {
              this.deviceListener(devices)
            }
          })
        }
      })
    } catch (e) {
      Logger.warn('DistributedService', 'subscribeDeviceChange failed: ' + (e as Error).message)
    }
  }

  // --- Distributed KV ---

  private async ensureKvStore(): Promise<distributedKVStore.DeviceKVStore | null> {
    if (this.kvStore) {
      return this.kvStore
    }
    try {
      const config: distributedKVStore.KVManagerConfig = {
        bundleName: 'com.lingxiflow.app',
        context: this.context!
      }
      const kvManager: distributedKVStore.KVManager = distributedKVStore.createKVManager(config)
      const options: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        backup: false,
        autoSync: true,
        securityLevel: distributedKVStore.SecurityLevel.S1,
        kvStoreType: distributedKVStore.KVStoreType.DEVICE_COLLABORATION
      }
      this.kvStore = await kvManager.getKVStore<distributedKVStore.DeviceKVStore>(STORE_ID, options)
      return this.kvStore
    } catch (e) {
      Logger.warn('DistributedService', 'ensureKvStore failed: ' + (e as Error).message)
      return null
    }
  }

  // Publish current task progress to all online devices (手机 → 平板/手表)
  async publishTaskState(payload: TaskStatePayload): Promise<void> {
    const store: distributedKVStore.DeviceKVStore | null = await this.ensureKvStore()
    if (!store) {
      return
    }
    try {
      await store.put(KEY_TASK_STATE, JSON.stringify(payload))
    } catch (e) {
      Logger.warn('DistributedService', 'publishTaskState failed: ' + (e as Error).message)
    }
  }

  async watchTaskState(listener: (payload: TaskStatePayload | null) => void): Promise<void> {
    const store: distributedKVStore.DeviceKVStore | null = await this.ensureKvStore()
    if (!store) {
      return
    }
    try {
      store.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL,
        (change: distributedKVStore.ChangeNotification): void => {
          const entries: distributedKVStore.Entry[] = change.insertEntries.concat(change.updateEntries)
          for (let i: number = 0; i < entries.length; i++) {
            if (entries[i].key === KEY_TASK_STATE) {
              store.get(KEY_TASK_STATE).then((value: string | number | boolean | Uint8Array): void => {
                try {
                  const payload: TaskStatePayload = JSON.parse(String(value)) as TaskStatePayload
                  listener(payload)
                } catch (_e) {
                  listener(null)
                }
              }).catch((): void => {
                listener(null)
              })
            }
          }
        })
    } catch (e) {
      Logger.warn('DistributedService', 'watchTaskState failed: ' + (e as Error).message)
    }
  }

  // Send a reminder command to other devices (手机创建提醒 → 手表同步提醒)
  async publishReminderCommand(cmd: ReminderCommand): Promise<void> {
    const store: distributedKVStore.DeviceKVStore | null = await this.ensureKvStore()
    if (!store) {
      return
    }
    try {
      await store.put(KEY_REMINDER_CMD, JSON.stringify(cmd))
    } catch (e) {
      Logger.warn('DistributedService', 'publishReminderCommand failed: ' + (e as Error).message)
    }
  }

  async watchReminderCommand(listener: (cmd: ReminderCommand) => void): Promise<void> {
    const store: distributedKVStore.DeviceKVStore | null = await this.ensureKvStore()
    if (!store) {
      return
    }
    try {
      store.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL,
        (change: distributedKVStore.ChangeNotification): void => {
          const entries: distributedKVStore.Entry[] = change.insertEntries.concat(change.updateEntries)
          for (let i: number = 0; i < entries.length; i++) {
            if (entries[i].key === KEY_REMINDER_CMD) {
              store.get(KEY_REMINDER_CMD).then((value: string | number | boolean | Uint8Array): void => {
                try {
                  const cmd: ReminderCommand = JSON.parse(String(value)) as ReminderCommand
                  listener(cmd)
                } catch (_e) {
                  // ignore malformed
                }
              }).catch((): void => {
                // ignore
              })
            }
          }
        })
    } catch (e) {
      Logger.warn('DistributedService', 'watchReminderCommand failed: ' + (e as Error).message)
    }
  }
}

export const distributedService: DistributedService = new DistributedService()
