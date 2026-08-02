// WeatherTools - Weather query tool for the agent
import { ToolRegistry } from '../engine/ToolRegistry'
import { Logger } from '../utils/Logger'
import { http } from '@kit.NetworkKit'

const SCHEMA_WEATHER: Record<string, Object> = JSON.parse('{"type":"object","properties":{"city":{"type":"string","description":"City name (optional)"}},"required":[]}') as Record<string, Object>

interface WeatherData {
  city: string
  temp: string
  weather: string
  humidity: string
  wind: string
}

async function fetchWeather(city: string): Promise<WeatherData> {
  try {
    const url: string = 'https://wttr.in/' + encodeURIComponent(city) + '?format=j1&lang=zh'
    const req: http.HttpRequest = http.createHttp()
    const resp: http.HttpResponse = await req.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 5000,
      readTimeout: 5000
    })
    if (resp.responseCode === 200) {
      const data: Record<string, Object> = JSON.parse(resp.result as string) as Record<string, Object>
      const current: Record<string, Object> = (data['current_condition'] as Array<Record<string, Object>>)[0]
      const nearest: Record<string, Object> = (data['nearest_area'] as Array<Record<string, Object>>)[0]
      const areaName: Record<string, Object> = (nearest['areaName'] as Array<Record<string, Object>>)[0]
      return {
        city: areaName['value'] as string || city,
        temp: current['temp_C'] as string || '?',
        weather: (current['weatherDesc'] as Array<Record<string, Object>>)[0]['value'] as string || '未知',
        humidity: current['humidity'] as string || '?',
        wind: (current['winddir16Point'] as string || '') + ' ' + (current['windspeedKmph'] as string || '') + 'km/h'
      }
    }
    req.destroy()
  } catch (e) {
    Logger.warn('WeatherTools', 'fetch failed: ' + (e as Error).message)
  }
  return { city: city, temp: '?', weather: '未知', humidity: '?', wind: '?' }
}

export function registerWeatherTools(registry: ToolRegistry): void {
  registry.registerTool(
    'get_weather',
    'Get current weather for a city. If no city specified, returns local weather.',
    SCHEMA_WEATHER,
    async (input: Record<string, Object>): Promise<string> => {
      const city: string = input['city'] as string || 'Beijing'
      const w: WeatherData = await fetchWeather(city)
      return w.city + ' 天气:\n  温度: ' + w.temp + '°C\n  天气: ' + w.weather +
        '\n  湿度: ' + w.humidity + '%\n  风力: ' + w.wind
    }
  )

  Logger.info('WeatherTools', 'Registered 1 weather tool')
}
