import { useMemo, useState } from 'react'
import { Alert, Box, Paper, Typography } from '@mui/material'
import ChatPanel from './components/ChatPanel'

async function* chatStreamWithProxy(message, sessionId = '') {
  const res = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, session_id: sessionId }),
  })

  if (!res.ok) {
    let detail = `HTTP ${res.status}`
    try {
      const body = await res.json()
      detail = body.detail ?? body.message ?? detail
    } catch {}
    throw new Error(detail)
  }

  const reader = res.body.getReader()
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

export default function EmbedApp() {
  const [messages, setMessages] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')

  const haloFirstName = useMemo(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get('firstName') || ''
  }, [])

  const haloEmail = useMemo(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get('email') || ''
  }, [])

  async function handleSend(text) {
    setError('')
    setMessages(prev => [...prev, { role: 'user', text }])
    setIsLoading(true)

    let assistantText = ''
    setMessages(prev => [...prev, { role: 'assistant', text: '', agent: '' }])

    try {
      for await (const event of chatStreamWithProxy(text)) {
        if (event.event === 'progress' && event.text) {
          assistantText += event.text
          setMessages(prev => {
            const updated = [...prev]
            updated[updated.length - 1] = {
              role: 'assistant',
              text: assistantText,
              agent: event.agent || updated[updated.length - 1].agent,
            }
            return updated
          })
        } else if (event.event === 'error') {
          setMessages(prev => {
            const updated = [...prev]
            updated[updated.length - 1] = {
              role: 'assistant',
              text: event.text || 'An error occurred processing your request.',
              agent: 'error',
            }
            return updated
          })
        }
      }
    } catch (err) {
      const message = err.message || 'Connection failed. Please try again.'
      setError(message)
      setMessages(prev => {
        const updated = [...prev]
        updated[updated.length - 1] = {
          role: 'assistant',
          text: message,
          agent: 'error',
        }
        return updated
      })
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <Box sx={{ minHeight: '100%', p: 1.5, bgcolor: 'transparent' }}>
      <Paper
        elevation={8}
        sx={{
          height: 'calc(100vh - 24px)',
          minHeight: 520,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          borderRadius: 3,
        }}
      >
        <Box sx={{ px: 2.5, py: 1.5, bgcolor: '#0f2027', color: '#fff' }}>
          <Typography variant="subtitle1" fontWeight={700}>
            ITSM AI Assistant
          </Typography>
          <Typography variant="caption" sx={{ opacity: 0.8 }}>
            {haloFirstName ? `Welcome, ${haloFirstName}` : 'Ask a question, search knowledge, or create a support ticket.'}
          </Typography>
          {haloEmail && (
            <Typography variant="caption" sx={{ display: 'block', mt: 0.75, opacity: 0.72 }}>
              Portal user context: {haloEmail}
            </Typography>
          )}
        </Box>
        {error && (
          <Alert severity="error" sx={{ m: 2, mb: 0 }}>
            {error}
          </Alert>
        )}
        <Box sx={{ flex: 1, minHeight: 0 }}>
          <ChatPanel messages={messages} isLoading={isLoading} onSend={handleSend} />
        </Box>
      </Paper>
    </Box>
  )
}