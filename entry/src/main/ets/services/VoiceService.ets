// VoiceService - Speech-to-text (ASR) and text-to-speech (TTS) via @kit.CoreSpeechKit
// ASR: mic audio captured by @kit.AudioKit audioCapturer -> writeAudio -> onResult
// TTS: online synthesis + playback, zh-CN
// API reference: HarmonyOS CoreSpeechKit Codelab (gitee.com/harmonyos_codelabs)
import { speechRecognizer } from '@kit.CoreSpeechKit'
import { textToSpeech } from '@kit.CoreSpeechKit'
import { audio } from '@kit.AudioKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Logger } from '../utils/Logger'

const ASR_LANGUAGE: string = 'zh-CN'
const TTS_LANGUAGE: string = 'zh-CN'
const SAMPLE_RATE: number = 16000
const MAX_TTS_CHARS: number = 500

export class VoiceService {
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null
  private capturer: audio.AudioCapturer | null = null
  private sessionId: string = ''
  private isListening: boolean = false
  private isSpeaking: boolean = false
  private currentResult: string = ''
  private asrErrorHandler: (message: string) => void = () => {}
  private asrDoneHandler: (text: string) => void = () => {}
  private ttsStopHandler: () => void = () => {}

  getListening(): boolean {
    return this.isListening
  }

  getSpeaking(): boolean {
    return this.isSpeaking
  }

  // --- ASR: start mic listening ---

  async startListening(
    onResult: (text: string) => void,
    onDone: (text: string) => void,
    onError: (message: string) => void
  ): Promise<void> {
    if (this.isListening) {
      return
    }
    this.asrErrorHandler = onError
    this.asrDoneHandler = onDone
    this.currentResult = ''
    this.isListening = true

    try {
      const engine: speechRecognizer.SpeechRecognitionEngine = await this.getAsrEngine()
      this.setAsrListener(engine, onResult)
      this.sessionId = 'asr_' + Date.now()

      const audioInfo: speechRecognizer.AudioInfo = {
        audioType: 'pcm',
        sampleRate: SAMPLE_RATE,
        soundChannel: 1,
        sampleBit: 16
      }
      const startParams: speechRecognizer.StartParams = {
        sessionId: this.sessionId,
        audioInfo: audioInfo
      }
      engine.startListening(startParams)

      const capturer: audio.AudioCapturer = await this.createCapturer()
      this.capturer = capturer
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        if (this.isListening && this.asrEngine) {
          this.asrEngine.writeAudio(this.sessionId, new Uint8Array(buffer))
        }
      })
      await capturer.start()
      Logger.info('VoiceService', 'ASR listening started, session=' + this.sessionId)
    } catch (e) {
      this.isListening = false
      this.asrErrorHandler('语音识别启动失败: ' + (e as Error).message)
      Logger.error('VoiceService', 'startListening failed: ' + (e as Error).message)
    }
  }

  // --- ASR: stop mic listening and finalize ---

  async stopListening(): Promise<void> {
    if (!this.isListening) {
      return
    }
    try {
      if (this.capturer) {
        await this.capturer.stop()
        this.capturer.release()
        this.capturer = null
      }
      if (this.asrEngine && this.sessionId.length > 0) {
        this.asrEngine.finish(this.sessionId)
      }
      Logger.info('VoiceService', 'ASR finished')
    } catch (e) {
      Logger.warn('VoiceService', 'stopListening: ' + (e as Error).message)
    }
    this.isListening = false
  }

  cancelListening(): void {
    if (!this.isListening) {
      return
    }
    try {
      if (this.capturer) {
        this.capturer.stop()
        this.capturer.release()
        this.capturer = null
      }
      if (this.asrEngine && this.sessionId.length > 0) {
        this.asrEngine.cancel(this.sessionId)
      }
    } catch (e) {
      Logger.warn('VoiceService', 'cancelListening: ' + (e as Error).message)
    }
    this.isListening = false
    this.sessionId = ''
  }

  private async getAsrEngine(): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.asrEngine) {
      return this.asrEngine
    }
    const extraParam: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'short'
    }
    const params: speechRecognizer.CreateEngineParams = {
      language: ASR_LANGUAGE,
      online: 1,
      extraParams: extraParam
    }
    const engine: speechRecognizer.SpeechRecognitionEngine = await new Promise<speechRecognizer.SpeechRecognitionEngine>(
      (resolve: (engine: speechRecognizer.SpeechRecognitionEngine) => void,
       reject: (err: BusinessError) => void): void => {
        speechRecognizer.createEngine(params, (err: BusinessError, created: speechRecognizer.SpeechRecognitionEngine): void => {
          if (err) {
            reject(err)
          } else {
            resolve(created)
          }
        })
      })
    this.asrEngine = engine
    return engine
  }

  private setAsrListener(engine: speechRecognizer.SpeechRecognitionEngine, onResult: (text: string) => void): void {
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string): void => {
        Logger.info('VoiceService', 'ASR onStart ' + sessionId + ' ' + eventMessage)
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
        Logger.info('VoiceService', 'ASR event ' + eventCode + ' ' + eventMessage)
      },
      onResult: (sessionId: string, res: speechRecognizer.SpeechRecognitionResult): void => {
        const text: string = res.result || ''
        if (text.length > 0) {
          this.currentResult = text
          onResult(text)
        }
      },
      onComplete: (sessionId: string, eventMessage: string): void => {
        Logger.info('VoiceService', 'ASR onComplete')
        const finalText: string = this.currentResult
        this.currentResult = ''
        this.sessionId = ''
        if (finalText.length > 0) {
          this.asrDoneHandler(finalText)
        }
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
        Logger.warn('VoiceService', 'ASR error ' + errorCode + ' ' + errorMessage)
        this.asrErrorHandler('语音识别出错(' + errorCode + '): ' + errorMessage)
      }
    }
    engine.setListener(listener)
  }

  private async createCapturer(): Promise<audio.AudioCapturer> {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    }
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    }
    const options: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    }
    return await audio.createAudioCapturer(options)
  }

  // --- TTS ---

  async speak(text: string, onStop?: () => void): Promise<void> {
    const cleanText: string = text.trim()
    if (cleanText.length === 0) {
      return
    }
    const speakText: string = cleanText.length > MAX_TTS_CHARS
      ? cleanText.substring(0, MAX_TTS_CHARS)
      : cleanText
    if (onStop) {
      this.ttsStopHandler = onStop
    }

    try {
      const engine: textToSpeech.TextToSpeechEngine = await this.getTtsEngine()
      this.setTtsListener(engine)
      const extraParam: Record<string, Object> = {
        'queueMode': 0,
        'speed': 1,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'soundChannel': 1,
        'playType': 1
      }
      const speakParams: textToSpeech.SpeakParams = {
        requestId: 'tts_' + Date.now(),
        extraParams: extraParam
      }
      this.isSpeaking = true
      engine.speak(speakText, speakParams)
      Logger.info('VoiceService', 'TTS speak: ' + speakText.length + ' chars')
    } catch (e) {
      this.isSpeaking = false
      Logger.warn('VoiceService', 'speak failed: ' + (e as Error).message)
    }
  }

  stopSpeaking(): void {
    if (!this.isSpeaking) {
      return
    }
    try {
      if (this.ttsEngine) {
        this.ttsEngine.stop()
      }
    } catch (e) {
      Logger.warn('VoiceService', 'stopSpeaking: ' + (e as Error).message)
    }
    this.isSpeaking = false
    this.ttsStopHandler()
  }

  private async getTtsEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.ttsEngine) {
      return this.ttsEngine
    }
    const extraParam: Record<string, Object> = {
      'style': 'interaction-broadcast',
      'locate': 'CN'
    }
    const params: textToSpeech.CreateEngineParams = {
      language: TTS_LANGUAGE,
      person: 0,
      online: 1,
      extraParams: extraParam
    }
    try {
      const engine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(params)
      this.ttsEngine = engine
      return engine
    } catch (e) {
      Logger.warn('VoiceService', 'TTS engine create failed: ' + (e as Error).message)
      throw e as Error
    }
  }

  private setTtsListener(engine: textToSpeech.TextToSpeechEngine): void {
    const listener: textToSpeech.SpeakListener = {
      onStart: (utteranceId: string, response: textToSpeech.StartResponse): void => {
        Logger.info('VoiceService', 'TTS onStart')
      },
      onComplete: (utteranceId: string, response: textToSpeech.CompleteResponse): void => {
        Logger.info('VoiceService', 'TTS onComplete')
        this.isSpeaking = false
        this.ttsStopHandler()
      },
      onStop: (utteranceId: string, response: textToSpeech.StopResponse): void => {
        Logger.info('VoiceService', 'TTS onStop')
        this.isSpeaking = false
        this.ttsStopHandler()
      },
      onData: (utteranceId: string, audioData: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
        // Audio stream output; playback is handled internally by playType=1
      },
      onError: (utteranceId: string, errorCode: number, errorMessage: string): void => {
        Logger.warn('VoiceService', 'TTS error ' + errorCode + ' ' + errorMessage)
        this.isSpeaking = false
        this.ttsStopHandler()
      }
    }
    engine.setListener(listener)
  }

  // --- Cleanup ---

  release(): void {
    try {
      this.cancelListening()
    } catch (e) {
      Logger.warn('VoiceService', 'release cancel: ' + (e as Error).message)
    }
    try {
      if (this.ttsEngine) {
        this.ttsEngine.shutdown()
        this.ttsEngine = null
      }
    } catch (e) {
      Logger.warn('VoiceService', 'release tts: ' + (e as Error).message)
    }
  }
}

export const voiceService: VoiceService = new VoiceService()
