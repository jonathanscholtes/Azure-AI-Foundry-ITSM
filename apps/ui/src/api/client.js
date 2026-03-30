/**
 * ITSM Service Desk API client.
 *
 * Connects to the itsm-api FastAPI service.
 * In development Vite proxies /chat → http://localhost:80.
 * In production nginx reverse-proxies to the API container.
 */

const BASE = import.meta.env.VITE_API_BASE ?? ''

/**
 * POST /chat — send a message and stream ndjson progress + result.
 *
 * Async generator that yields parsed event objects as they arrive:
 *   { event: 'progress', agent: 'classifier', status: 'running' }
 *   { event: 'progress', agent: 'kb_lookup',  text: '...' }
 *   { event: 'complete' }
 *   { event: 'error',    text: '...' }
 *
 * @param {string} message — user's chat message
 * @param {string} sessionId — optional session identifier
 * @yields {Object} parsed ndjson event
 */
export async function* chatStream(message, sessionId = '') {
  const res = await fetch(`${BASE}/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, session_id: sessionId }),
  })

  if (!res.ok) {
    let detail = `HTTP ${res.status}`
    try {
      const body = await res.json()
      detail = body.detail ?? body.message ?? detail
    } catch { /* ignore */ }
    throw new Error(detail)
  }

  const reader  = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop()
    for (const line of lines) {
      const trimmed = line.trim()
      if (trimmed) yield JSON.parse(trimmed)
    }
  }
  if (buffer.trim()) yield JSON.parse(buffer.trim())
}

/**
 * GET /health — liveness check.
 *
 * @returns {Promise<{ status: string, environment: string }>}
 */
export async function getHealth() {
  const res = await fetch(`${BASE}/health`)
  if (!res.ok) throw new Error(`Health check failed: HTTP ${res.status}`)
  return res.json()
}
