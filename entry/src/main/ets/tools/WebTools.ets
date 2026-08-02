// WebTools - Web search and page fetch tools for the agent
// Primary: Bing (cn.bing.com, works in China, no API key)
// Fallback: DuckDuckGo HTML search (works on international networks)
// + HTTP page fetching with HTML tag stripping
// Adapted from NanoClaw tools/WebTools.ets for the China network environment
import { http } from '@kit.NetworkKit'
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'
import { stripHtmlTags, truncateText } from '../utils/TextFormatter'

const SCHEMA_SEARCH: Record<string, Object> = JSON.parse('{"type":"object","properties":{"query":{"type":"string","description":"Search query keyword"}},"required":["query"]}') as Record<string, Object>

const SCHEMA_FETCH: Record<string, Object> = JSON.parse('{"type":"object","properties":{"url":{"type":"string","description":"The URL of the web page to fetch"}},"required":["url"]}') as Record<string, Object>

const MAX_RESULTS: number = 8
const MAX_FETCH_CHARS: number = 50000
const BING_URL: string = 'https://cn.bing.com/search?q='
const DDG_URL: string = 'https://html.duckduckgo.com/html/?q='

interface SearchResult {
  title: string
  url: string
  snippet: string
}

// --- HTTP helpers ---

async function httpGetText(url: string): Promise<string> {
  const req: http.HttpRequest = http.createHttp()
  const resp: http.HttpResponse = await req.request(url, {
    method: http.RequestMethod.GET,
    header: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 15; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,text/plain'
    },
    connectTimeout: 10000,
    readTimeout: 20000
  })
  req.destroy()
  if (resp.responseCode !== 200) {
    return ''
  }
  return resp.result as string
}

// --- Bing parser (cn.bing.com) ---
// Structure: <li class="b_algo"><div class="b_algoheader"><a href="URL" h="..."><h2>TITLE</h2></a></div>
//            <div class="b_caption"><p class="b_lineclamp3">SNIPPET</p></div></li>

function extractBingResults(html: string): SearchResult[] {
  const results: SearchResult[] = []
  const blocks: string[] = html.split('b_algo')
  for (let i: number = 1; i < blocks.length && results.length < MAX_RESULTS; i++) {
    const block: string = blocks[i]
    const h2Start: number = block.indexOf('<h2')
    if (h2Start < 0) {
      continue
    }
    const h2TagEnd: number = block.indexOf('>', h2Start)
    const h2End: number = block.indexOf('</h2>', h2Start)
    if (h2TagEnd < 0 || h2End < 0) {
      continue
    }
    const title: string = stripHtmlTags(block.substring(h2TagEnd + 1, h2End)).trim()
    if (title.length === 0) {
      continue
    }

    // Nearest <a href> before the h2 tag
    let url: string = ''
    const before: string = block.substring(0, h2Start)
    const hrefMatches: RegExpMatchArray | null = before.match(/href="([^"]+)"/g)
    if (hrefMatches && hrefMatches.length > 0) {
      const lastHref: string = hrefMatches[hrefMatches.length - 1]
      if (lastHref.length > 6) {
        url = lastHref.substring(6, lastHref.length - 1)
      }
    }
    if (url.length === 0) {
      continue
    }
    if (url.indexOf('http') !== 0) {
      url = 'https://cn.bing.com' + url
    }

    // First <p> after the h2 as snippet
    let snippet: string = ''
    const pStart: number = block.indexOf('<p', h2End)
    if (pStart >= 0) {
      const pEnd: number = block.indexOf('</p>', pStart)
      if (pEnd > pStart) {
        snippet = stripHtmlTags(block.substring(pStart, pEnd)).trim()
      }
    }

    results.push({ title: title, url: url, snippet: snippet })
  }
  return results
}

// --- DuckDuckGo parser (fallback) ---

function decodeDdgUrl(href: string): string {
  if (href.indexOf('uddg=') >= 0) {
    const parts: string[] = href.split('uddg=')
    if (parts.length > 1) {
      let u: string = parts[1]
      const amp: number = u.indexOf('&')
      if (amp >= 0) {
        u = u.substring(0, amp)
      }
      try {
        return decodeURIComponent(u)
      } catch (_e) {
        return u
      }
    }
  }
  return href
}

function extractDdgResults(html: string): SearchResult[] {
  const results: SearchResult[] = []
  const blocks: string[] = html.split('result__body')
  for (let i: number = 1; i < blocks.length && results.length < MAX_RESULTS; i++) {
    const block: string = blocks[i]
    const titleMatch: RegExpMatchArray | null = block.match(/result__a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/)
    if (!titleMatch) {
      continue
    }
    const url: string = decodeDdgUrl(titleMatch[1])
    const title: string = stripHtmlTags(titleMatch[2]).trim()
    if (title.length === 0) {
      continue
    }
    const snippetMatch: RegExpMatchArray | null = block.match(/result__snippet[^>]*>(.*?)<\/a>/)
    let snippet: string = ''
    if (snippetMatch) {
      snippet = stripHtmlTags(snippetMatch[1]).trim()
    }
    results.push({ title: title, url: url, snippet: snippet })
  }
  return results
}

function formatResults(query: string, engine: string, results: SearchResult[]): string {
  if (results.length === 0) {
    return '未找到与 "' + query + '" 相关的结果'
  }
  let out: string = '关于 "' + query + '" 的搜索结果（来源: ' + engine + '，' + results.length + ' 条）:\n'
  for (let i: number = 0; i < results.length; i++) {
    const r: SearchResult = results[i]
    out += '\n' + (i + 1) + '. ' + r.title + '\n'
    out += '   链接: ' + r.url + '\n'
    if (r.snippet.length > 0) {
      out += '   摘要: ' + r.snippet + '\n'
    }
  }
  return out
}

// --- Tools ---

async function webSearch(input: Record<string, Object>): Promise<string> {
  const query: string = (input['query'] as string) || ''
  if (query.length === 0) {
    return 'Error: query is required'
  }

  const encodedQuery: string = encodeURIComponent(query)

  // 1) Try Bing first (works in mainland China)
  try {
    const bingHtml: string = await httpGetText(BING_URL + encodedQuery + '&setlang=zh-cn')
    if (bingHtml.length > 0) {
      const bingResults: SearchResult[] = extractBingResults(bingHtml)
      if (bingResults.length > 0) {
        return formatResults(query, 'Bing', bingResults)
      }
    }
  } catch (_e) {
    // fall through to DDG
  }

  // 2) Fallback: DuckDuckGo (international networks)
  try {
    const ddgHtml: string = await httpGetText(DDG_URL + encodedQuery)
    if (ddgHtml.length > 0) {
      const ddgResults: SearchResult[] = extractDdgResults(ddgHtml)
      if (ddgResults.length > 0) {
        return formatResults(query, 'DuckDuckGo', ddgResults)
      }
    }
  } catch (_e) {
    // fall through
  }

  return '搜索失败: 无法访问搜索引擎（请检查网络连接）'
}

async function webFetch(input: Record<string, Object>): Promise<string> {
  const url: string = (input['url'] as string) || ''
  if (url.length === 0) {
    return 'Error: url is required'
  }

  try {
    const body: string = await httpGetText(url)
    if (body.length === 0) {
      return '抓取失败: 无法访问 ' + url
    }
    const text: string = stripHtmlTags(body)
    return truncateText(text, MAX_FETCH_CHARS)
  } catch (e) {
    return '抓取出错: ' + (e as Error).message
  }
}

export function registerWebTools(registry: ToolRegistry): void {
  registry.registerTool(
    'web_search',
    'Search the web (Bing, fallback DuckDuckGo). Returns titles, links and snippets. Use when the user asks about news, facts, information or anything outside local files.',
    SCHEMA_SEARCH,
    webSearch
  )

  registry.registerTool(
    'web_fetch',
    'Fetch the text content of a web page (HTML tags stripped). Use with a URL from web_search to read full article content.',
    SCHEMA_FETCH,
    webFetch
  )

  Logger.info('WebTools', 'Registered 2 web tools')
}
