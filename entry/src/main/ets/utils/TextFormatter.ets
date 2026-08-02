// TextFormatter - Utility functions
// Ported from NanoClaw text formatter

export function generateId(): string {
  const timestamp: string = Date.now().toString(36)
  const random: string = Math.random().toString(36).substring(2, 8)
  return timestamp + '_' + random
}

export function escapeXml(input: string): string {
  let result: string = input
  result = result.replace(/&/g, '&amp;')
  result = result.replace(/</g, '&lt;')
  result = result.replace(/>/g, '&gt;')
  result = result.replace(/\u0022/g, '&quot;')
  result = result.replace(/\u0027/g, '&apos;')
  return result
}

export function stripHtmlTags(input: string): string {
  let result: string = input
  // Remove script/style blocks first (their content is not page text)
  result = result.replace(/<script[\s\S]*?<\/script>/gi, ' ')
  result = result.replace(/<style[\s\S]*?<\/style>/gi, ' ')
  // Remove remaining tags, collapse whitespace
  result = result.replace(/<[^>]*>/g, ' ')
  result = result.replace(/\s+/g, ' ')
  return result.trim()
}

export function truncateText(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text
  }
  return text.substring(0, maxLength) + '...'
}
