// RagService - Retrieval-Augmented Generation over the local knowledge base
// Knowledge sources (all inside the app sandbox):
//   filesDir/memory/*.md      - AI memory notes (from MemoryTools)
//   filesDir/knowledge/*      - user documents (.md / .txt)
//   filesDir/*.md, *.txt      - root-level documents
// Embeddings: SiliconFlow BGE-M3 (OpenAI-compatible /v1/embeddings, reachable in China)
// Storage: SQLite lingxi_rag.db (chunks + float32 blobs)
// Retrieval: cosine similarity; keyword bigram fallback when no embedding key configured
// Adapted from NanoClaw VectorRagService.ets
import { relationalStore } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { fileIo } from '@kit.CoreFileKit'
import { Logger } from '../utils/Logger'
import { configService } from '../services/ConfigService'

const DB_NAME: string = 'lingxi_rag.db'
const TABLE_CHUNKS: string = 'rag_chunks'
const TABLE_META: string = 'rag_meta'
const CHUNK_SIZE: number = 400
const CHUNK_OVERLAP: number = 60
const BATCH_SIZE: number = 5
const DEFAULT_TOP_K: number = 3
const EMBED_MODEL: string = 'BAAI/bge-m3'

const CREATE_CHUNKS_SQL: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_CHUNKS + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'doc_id TEXT NOT NULL,' +
  'chunk_index INTEGER NOT NULL,' +
  'chunk_text TEXT NOT NULL,' +
  'embedding BLOB)'

const CREATE_META_SQL: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_META + ' (' +
  'key TEXT PRIMARY KEY,' +
  'value TEXT NOT NULL)'

interface EmbeddingRequestBody {
  model: string
  input: string[]
  encoding_format: string
}

interface EmbeddingDataItem {
  embedding: number[]
  index: number
  object: string
}

interface EmbeddingResponseBody {
  data: EmbeddingDataItem[]
  model: string
  object: string
}

interface ScoredChunk {
  text: string
  score: number
}

type RagStatus = 'uninitialized' | 'indexing' | 'ready' | 'fallback'

export interface SourceFileInfo {
  name: string
  size: number
}

export class RagService {
  private store: relationalStore.RdbStore | null = null
  private filesDir: string = ''
  private status: RagStatus = 'uninitialized'
  private dirty: boolean = true
  private buildPromise: Promise<void> | null = null
  private embedKey: string = ''
  private embedUrl: string = ''

  getStatus(): RagStatus {
    return this.status
  }

  getFilesDir(): string {
    return this.filesDir
  }

  async init(context: common.UIAbilityContext, filesDir: string): Promise<void> {
    this.filesDir = filesDir
    this.embedKey = await configService.getEmbeddingKey()
    this.embedUrl = await configService.getEmbeddingUrl()
    try {
      const storeConfig: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      }
      this.store = await relationalStore.getRdbStore(context, storeConfig)
      await this.store.executeSql(CREATE_CHUNKS_SQL)
      await this.store.executeSql(CREATE_META_SQL)
      Logger.info('RagService', 'DB ready, mode=' + (this.embedKey.length > 0 ? 'vector' : 'keyword'))
    } catch (e) {
      Logger.error('RagService', 'DB init failed: ' + (e as Error).message)
    }
  }

  // Called by MemoryTools after notes change - next retrieval rebuilds the index
  markDirty(): void {
    this.dirty = true
  }

  // Force an index rebuild on next retrieval
  forceRebuild(): void {
    this.dirty = true
    this.buildIndexIfNeeded()
  }

  // --- Info for the knowledge base management page ---

  async getChunkCount(): Promise<number> {
    if (!this.store) {
      return 0
    }
    try {
      const resultSet: relationalStore.ResultSet = await this.store.querySql(
        'SELECT COUNT(*) AS c FROM ' + TABLE_CHUNKS)
      let count: number = 0
      if (resultSet.goToNextRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('c'))
      }
      resultSet.close()
      return count
    } catch (e) {
      return 0
    }
  }

  // List knowledge source files: [path, size] pairs for the management page
  async getSourceFiles(): Promise<SourceFileInfo[]> {
    const result: SourceFileInfo[] = []
    const dirs: string[] = [this.filesDir + '/memory', this.filesDir + '/knowledge']
    for (let i: number = 0; i < dirs.length; i++) {
      try {
        const names: string[] = fileIo.listFileSync(dirs[i])
        for (let j: number = 0; j < names.length; j++) {
          const n: string = names[j]
          if (!n.endsWith('.md') && !n.endsWith('.txt')) {
            continue
          }
          try {
            const st: fileIo.Stat = fileIo.statSync(dirs[i] + '/' + n)
            const info: SourceFileInfo = {
              name: (dirs[i].endsWith('/memory') ? '记忆/' : '知识库/') + n,
              size: st.size
            }
            result.push(info)
          } catch (_e) {
            // skip unreadable
          }
        }
      } catch (_e) {
        // dir may not exist
      }
    }
    try {
      const rootNames: string[] = fileIo.listFileSync(this.filesDir)
      for (let k: number = 0; k < rootNames.length; k++) {
        const n: string = rootNames[k]
        if ((!n.endsWith('.md') && !n.endsWith('.txt')) || n === 'note.txt') {
          continue
        }
        try {
          const st: fileIo.Stat = fileIo.statSync(this.filesDir + '/' + n)
          const info: SourceFileInfo = { name: '根目录/' + n, size: st.size }
          result.push(info)
        } catch (_e) {
          // skip
        }
      }
    } catch (_e) {
      // ignore
    }
    return result
  }

  // --- Index building (single-flight) ---

  buildIndexIfNeeded(): Promise<void> {
    if (this.buildPromise) {
      return this.buildPromise
    }
    const p: Promise<void> = this.doBuildIndex()
    this.buildPromise = p
    p.then((): void => {
      if (this.buildPromise === p) {
        this.buildPromise = null
      }
    }).catch((): void => {
      if (this.buildPromise === p) {
        this.buildPromise = null
      }
    })
    return p
  }

  private async doBuildIndex(): Promise<void> {
    if (!this.store) {
      return
    }
    const chunks: string[] = this.collectChunks()
    const signature: string = this.contentSignature()
    const stored: string = await this.getMetaValue('content_signature')
    if (!this.dirty && stored === signature) {
      if (this.status === 'uninitialized') {
        this.status = chunks.length > 0 ? 'ready' : 'fallback'
      }
      return
    }
    this.dirty = false
    this.status = 'indexing'
    Logger.info('RagService', 'building index: ' + chunks.length + ' chunks')

    try {
      await this.store.executeSql('DELETE FROM ' + TABLE_CHUNKS)
      const useVector: boolean = this.embedKey.length > 0

      for (let i: number = 0; i < chunks.length; i += BATCH_SIZE) {
        const end: number = Math.min(i + BATCH_SIZE, chunks.length)
        const batchTexts: string[] = []
        for (let j: number = i; j < end; j++) {
          batchTexts.push(chunks[j])
        }

        let vectors: number[][] | null = null
        if (useVector) {
          vectors = await this.callEmbeddingApi(batchTexts)
        }

        for (let k: number = 0; k < batchTexts.length; k++) {
          const blob: Uint8Array = vectors ? this.floatArrayToBlob(vectors[k]) : new Uint8Array(0)
          const row: relationalStore.ValuesBucket = {
            'doc_id': 'doc_' + (i + k),
            'chunk_index': i + k,
            'chunk_text': batchTexts[k],
            'embedding': blob
          }
          await this.store.insert(TABLE_CHUNKS, row)
        }
      }

      await this.setMetaValue('content_signature', signature)
      this.status = useVector ? 'ready' : 'fallback'
      Logger.info('RagService', 'index built: ' + chunks.length + ' chunks, mode=' + (useVector ? 'vector' : 'keyword'))
    } catch (e) {
      Logger.error('RagService', 'buildIndex failed: ' + (e as Error).message)
      this.status = 'fallback'
      // Rebuild may have wiped the table - retry on next retrieval instead of staying empty
      this.dirty = true
    }
  }

  // --- Retrieval ---

  async retrieve(query: string, topK?: number): Promise<string[]> {
    const k: number = topK !== undefined ? topK : DEFAULT_TOP_K
    if (!this.store || query.length === 0) {
      return []
    }
    await this.buildIndexIfNeeded()

    try {
      const useVector: boolean = this.status === 'ready'
      const chunks: ScoredChunk[] = []

      if (useVector) {
        const queryVec: number[] | null = await this.queryEmbedding(query)
        if (queryVec) {
          const resultSet: relationalStore.ResultSet = await this.store.querySql(
            'SELECT chunk_text, embedding FROM ' + TABLE_CHUNKS)
          while (resultSet.goToNextRow()) {
            const text: string = resultSet.getString(resultSet.getColumnIndex('chunk_text'))
            const blob: Uint8Array = resultSet.getBlob(resultSet.getColumnIndex('embedding'))
            const vec: number[] = this.blobToFloatArray(blob)
            const score: number = this.cosineSimilarity(queryVec, vec)
            chunks.push({ text: text, score: score })
          }
          resultSet.close()
        }
      } else {
        const resultSet: relationalStore.ResultSet = await this.store.querySql(
          'SELECT chunk_text FROM ' + TABLE_CHUNKS)
        while (resultSet.goToNextRow()) {
          const text: string = resultSet.getString(resultSet.getColumnIndex('chunk_text'))
          const score: number = this.keywordScore(query, text)
          chunks.push({ text: text, score: score })
        }
        resultSet.close()
      }

      chunks.sort((a: ScoredChunk, b: ScoredChunk): number => b.score - a.score)
      const results: string[] = []
      for (let i: number = 0; i < chunks.length && i < k; i++) {
        if (chunks[i].score > 0.01) {
          results.push(chunks[i].text)
        }
      }
      Logger.info('RagService', 'retrieved ' + results.length + '/' + chunks.length +
        ' chunks (mode=' + (useVector ? 'vector' : 'keyword') + ')')
      return results
    } catch (e) {
      Logger.error('RagService', 'retrieve failed: ' + (e as Error).message)
      return []
    }
  }

  private async queryEmbedding(query: string): Promise<number[] | null> {
    const vectors: number[][] | null = await this.callEmbeddingApi([query])
    if (vectors && vectors.length > 0) {
      return vectors[0]
    }
    return null
  }

  // --- Knowledge sources ---

  private collectChunks(): string[] {
    const chunks: string[] = []
    const dirs: string[] = []
    const memoryDir: string = this.filesDir + '/memory'
    const kbDir: string = this.filesDir + '/knowledge'
    try {
      const memoryFiles: string[] = fileIo.listFileSync(memoryDir)
      for (let i: number = 0; i < memoryFiles.length; i++) {
        if (memoryFiles[i].endsWith('.md')) {
          dirs.push(memoryDir + '/' + memoryFiles[i])
        }
      }
    } catch (_e) {
      // memory dir may not exist yet
    }
    try {
      const kbFiles: string[] = fileIo.listFileSync(kbDir)
      for (let j: number = 0; j < kbFiles.length; j++) {
        if (kbFiles[j].endsWith('.md') || kbFiles[j].endsWith('.txt')) {
          dirs.push(kbDir + '/' + kbFiles[j])
        }
      }
    } catch (_e) {
      // knowledge dir may not exist yet
    }
    try {
      const rootFiles: string[] = fileIo.listFileSync(this.filesDir)
      for (let k: number = 0; k < rootFiles.length; k++) {
        const name: string = rootFiles[k]
        if ((name.endsWith('.md') || name.endsWith('.txt')) && name !== 'note.txt') {
          dirs.push(this.filesDir + '/' + name)
        }
      }
    } catch (_e) {
      // ignore
    }
    for (let d: number = 0; d < dirs.length; d++) {
      try {
        const content: string = fileIo.readTextSync(dirs[d])
        const fileChunks: string[] = this.chunkize(content)
        for (let c: number = 0; c < fileChunks.length; c++) {
          chunks.push(fileChunks[c])
        }
      } catch (_e) {
        // unreadable file - skip
      }
    }
    return chunks
  }

  // Split long text into overlapping chunks on paragraph boundaries
  private chunkize(text: string): string[] {
    const result: string[] = []
    const paragraphs: string[] = text.split('\n')
    let current: string = ''
    for (let i: number = 0; i < paragraphs.length; i++) {
      const p: string = paragraphs[i].trim()
      if (p.length === 0) {
        continue
      }
      if (current.length + p.length + 1 > CHUNK_SIZE && current.length > 0) {
        result.push(current)
        // overlap: keep the tail of the current chunk
        current = current.length > CHUNK_OVERLAP ? current.substring(current.length - CHUNK_OVERLAP) : ''
      }
      current = current.length > 0 ? current + '\n' + p : p
    }
    if (current.length > 0) {
      result.push(current)
    }
    return result
  }

  private contentSignature(): string {
    let sig: string = ''
    const paths: string[] = [this.filesDir + '/memory', this.filesDir + '/knowledge', this.filesDir]
    for (let i: number = 0; i < paths.length; i++) {
      try {
        const names: string[] = fileIo.listFileSync(paths[i])
        for (let j: number = 0; j < names.length; j++) {
          const n: string = names[j]
          if (!n.endsWith('.md') && !n.endsWith('.txt')) {
            continue
          }
          try {
            const st: fileIo.Stat = fileIo.statSync(paths[i] + '/' + n)
            sig += n + ':' + st.size + ':' + st.mtime + ';'
          } catch (_e) {
            // skip
          }
        }
      } catch (_e) {
        // skip missing dir
      }
    }
    return sig
  }

  // --- Embedding API (SiliconFlow / OpenAI-compatible) ---

  private async callEmbeddingApi(texts: string[]): Promise<number[][] | null> {
    if (this.embedKey.length === 0) {
      return null
    }
    const body: EmbeddingRequestBody = {
      model: EMBED_MODEL,
      input: texts,
      encoding_format: 'float'
    }
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(this.embedUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + this.embedKey
        },
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 60000
      })
      req.destroy()
      if (resp.responseCode !== 200) {
        Logger.warn('RagService', 'embedding api http ' + resp.responseCode)
        return null
      }
      const parsed: EmbeddingResponseBody = JSON.parse(resp.result as string) as EmbeddingResponseBody
      if (!parsed.data || parsed.data.length === 0) {
        return null
      }
      // Sort by index to keep request order
      const items: EmbeddingDataItem[] = parsed.data.slice()
      items.sort((a: EmbeddingDataItem, b: EmbeddingDataItem): number => a.index - b.index)
      const vectors: number[][] = []
      for (let i: number = 0; i < items.length; i++) {
        vectors.push(items[i].embedding)
      }
      return vectors
    } catch (e) {
      req.destroy()
      Logger.warn('RagService', 'embedding api failed: ' + (e as Error).message)
      return null
    }
  }

  // --- Vector math ---

  private cosineSimilarity(a: number[], b: number[]): number {
    let dot: number = 0
    let normA: number = 0
    let normB: number = 0
    const len: number = Math.min(a.length, b.length)
    for (let i: number = 0; i < len; i++) {
      dot += a[i] * b[i]
      normA += a[i] * a[i]
      normB += b[i] * b[i]
    }
    if (normA === 0 || normB === 0) {
      return 0
    }
    return dot / (Math.sqrt(normA) * Math.sqrt(normB))
  }

  // Keyword fallback: character-bigram overlap ratio (works for Chinese)
  private keywordScore(query: string, text: string): number {
    const bigrams: string[] = []
    for (let i: number = 0; i < query.length - 1; i++) {
      const bg: string = query.substring(i, i + 2)
      if (bigrams.indexOf(bg) < 0) {
        bigrams.push(bg)
      }
    }
    if (bigrams.length === 0) {
      return 0
    }
    let hits: number = 0
    for (let j: number = 0; j < bigrams.length; j++) {
      if (text.indexOf(bigrams[j]) >= 0) {
        hits++
      }
    }
    return hits / bigrams.length
  }

  private floatArrayToBlob(arr: number[]): Uint8Array {
    const float32: Float32Array = new Float32Array(arr.length)
    for (let i: number = 0; i < arr.length; i++) {
      float32[i] = arr[i]
    }
    return new Uint8Array(float32.buffer)
  }

  private blobToFloatArray(blob: Uint8Array): number[] {
    const result: number[] = []
    if (!blob || blob.length === 0) {
      return result
    }
    const float32: Float32Array = new Float32Array(blob.buffer, blob.byteOffset, blob.byteLength / 4)
    for (let i: number = 0; i < float32.length; i++) {
      result.push(float32[i])
    }
    return result
  }

  // --- Metadata ---

  private async getMetaValue(key: string): Promise<string> {
    if (!this.store) {
      return ''
    }
    try {
      const resultSet: relationalStore.ResultSet = await this.store.querySql(
        'SELECT value FROM ' + TABLE_META + ' WHERE key = ?', [key])
      let value: string = ''
      if (resultSet.goToNextRow()) {
        value = resultSet.getString(0)
      }
      resultSet.close()
      return value
    } catch (e) {
      return ''
    }
  }

  private async setMetaValue(key: string, value: string): Promise<void> {
    if (!this.store) {
      return
    }
    try {
      await this.store.executeSql('DELETE FROM ' + TABLE_META + ' WHERE key = ?', [key])
      const row: relationalStore.ValuesBucket = {
        'key': key,
        'value': value
      }
      await this.store.insert(TABLE_META, row)
    } catch (e) {
      Logger.error('RagService', 'setMetaValue failed: ' + (e as Error).message)
    }
  }
}

export const ragService: RagService = new RagService()
