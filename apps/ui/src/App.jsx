import { useState, useCallback } from 'react'
import {
  Box, AppBar, Toolbar, Typography, Divider,
  IconButton, Avatar, Tooltip, Button, Paper, InputBase, Badge,
} from '@mui/material'
import SearchIcon from '@mui/icons-material/Search'
import NotificationsNoneOutlinedIcon from '@mui/icons-material/NotificationsNoneOutlined'
import AddIcon from '@mui/icons-material/Add'
import HelpOutlineIcon from '@mui/icons-material/HelpOutline'
import TrendingUpIcon from '@mui/icons-material/TrendingUp'
import TrendingDownIcon from '@mui/icons-material/TrendingDown'
import AccessTimeIcon from '@mui/icons-material/AccessTime'
import VerifiedOutlinedIcon from '@mui/icons-material/VerifiedOutlined'
import AssignmentLateOutlinedIcon from '@mui/icons-material/AssignmentLateOutlined'
import ConfirmationNumberOutlinedIcon from '@mui/icons-material/ConfirmationNumberOutlined'
import Sidebar from './components/Sidebar'
import ChatPanel from './components/ChatPanel'
import { chatStream } from './api/client'

const STATS = [
  { label: 'Open Incidents', value: '42', sub: '+3 today', icon: <ConfirmationNumberOutlinedIcon />, color: '#0078D4', trend: 'up' },
  { label: 'Avg Response', value: '1.2 hrs', sub: '\u22120.3 from last week', icon: <AccessTimeIcon />, color: '#16A34A', trend: 'down' },
  { label: 'SLA Compliance', value: '94.2%', sub: 'Target: 95%', icon: <VerifiedOutlinedIcon />, color: '#00B7C3', trend: 'up' },
  { label: 'Unassigned', value: '7', sub: '2 critical', icon: <AssignmentLateOutlinedIcon />, color: '#F59E0B' },
]

export default function App() {
  const [messages, setMessages] = useState([])
  const [agentStatuses, setAgentStatuses] = useState({
    classifier: 'idle', kb_lookup: 'idle', ticket: 'idle', triage: 'idle',
  })
  const [activityLog, setActivityLog] = useState([])
  const [isLoading, setIsLoading] = useState(false)

  /** Append an entry to the activity feed. */
  const addActivity = useCallback((agent, text) => {
    setActivityLog(prev => [
      { agent, text, ts: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) },
      ...prev,
    ].slice(0, 20))
  }, [])

  const handleSend = useCallback(async (text) => {
    const userMsg = { role: 'user', text }
    setMessages(prev => [...prev, userMsg])
    setIsLoading(true)
    setAgentStatuses({ classifier: 'idle', kb_lookup: 'idle', ticket: 'idle', triage: 'idle' })

    let assistantText = ''

    setMessages(prev => [...prev, { role: 'assistant', text: '', agent: '' }])

    try {
      for await (const event of chatStream(text)) {
        if (event.event === 'progress') {
          if (event.status) {
            setAgentStatuses(prev => ({ ...prev, [event.agent]: event.status }))
            if (event.status === 'running') {
              addActivity(event.agent, `${event.agent} started`)
            }
          }
          if (event.text) {
            assistantText += event.text
            setMessages(prev => {
              const updated = [...prev]
              const idx = updated.length - 1
              updated[idx] = {
                role: 'assistant',
                text: assistantText,
                agent: event.agent || updated[idx].agent,
              }
              return updated
            })
          }
          if (event.agent && !event.status) {
            setAgentStatuses(prev => ({ ...prev, [event.agent]: 'running' }))
          }
        } else if (event.event === 'complete') {
          setAgentStatuses(prev => {
            const next = { ...prev }
            for (const k of Object.keys(next)) {
              if (next[k] === 'running') {
                next[k] = 'done'
                addActivity(k, `${k} completed`)
              }
            }
            return next
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
          addActivity('error', 'Pipeline error')
        }
      }
    } catch (err) {
      setMessages(prev => {
        const updated = [...prev]
        updated[updated.length - 1] = {
          role: 'assistant',
          text: err.message || 'Connection failed. Please try again.',
          agent: 'error',
        }
        return updated
      })
      addActivity('error', err.message || 'Connection failed')
    } finally {
      setIsLoading(false)
    }
  }, [addActivity])

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: '#f5f6f8' }}>
      <Sidebar activityLog={activityLog} />

      <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* Top bar */}
        <AppBar position="static" elevation={0} sx={{
          bgcolor: '#fff',
          borderBottom: '1px solid #e5e7eb',
        }}>
          <Toolbar sx={{ minHeight: '52px !important', px: { xs: 2, md: 3 } }}>
            <Box sx={{ flexGrow: 1 }}>
              <Typography variant="subtitle1" color="text.primary" fontWeight={600} sx={{ fontSize: '0.95rem' }}>
                AI Assistant
              </Typography>
            </Box>

            <Paper elevation={0} sx={{
              display: 'flex', alignItems: 'center', px: 1.5, py: 0.25,
              bgcolor: '#f5f6f8', borderRadius: 2, mr: 1.5, width: 200,
              border: '1px solid #e5e7eb',
            }}>
              <SearchIcon sx={{ fontSize: 18, color: 'text.secondary', mr: 0.5 }} />
              <InputBase placeholder="Search..." sx={{ fontSize: '0.8rem', flexGrow: 1 }} />
            </Paper>

            <Tooltip title="Notifications">
              <IconButton size="small" sx={{ mr: 0.5 }}>
                <Badge badgeContent={3} color="error" sx={{ '& .MuiBadge-badge': { fontSize: '0.6rem', height: 16, minWidth: 16 } }}>
                  <NotificationsNoneOutlinedIcon fontSize="small" />
                </Badge>
              </IconButton>
            </Tooltip>

            <Tooltip title="Help">
              <IconButton size="small" sx={{ mr: 1 }}>
                <HelpOutlineIcon fontSize="small" />
              </IconButton>
            </Tooltip>

            <Button
              variant="contained"
              size="small"
              startIcon={<AddIcon sx={{ fontSize: 16 }} />}
              onClick={() => { if (!isLoading) handleSend('I need to create a new support ticket') }}
              sx={{
                ml: 0.5, mr: 1.5,
                textTransform: 'none',
                fontWeight: 600,
                fontSize: '0.75rem',
                px: 1.5, py: 0.5,
                borderRadius: 1.5,
                boxShadow: 'none',
                '&:hover': { boxShadow: 'none' },
              }}
            >
              New Ticket
            </Button>

            <Divider orientation="vertical" flexItem sx={{ mr: 1.5, my: 1 }} />

            <Tooltip title="Jonathan Scholtes">
              <Avatar sx={{
                width: 30, height: 30, bgcolor: '#0078D4',
                fontSize: '0.7rem', fontWeight: 600, cursor: 'pointer',
              }}>
                JS
              </Avatar>
            </Tooltip>
          </Toolbar>
        </AppBar>

        {/* Stats row */}
        <Box sx={{
          display: 'flex', gap: 2, px: { xs: 2, md: 3 }, py: 2,
          borderBottom: '1px solid #e5e7eb',
          bgcolor: '#fff',
        }}>
          {STATS.map((s) => (
            <Paper key={s.label} elevation={0} sx={{
              flex: 1, p: 2, borderRadius: 2,
              border: '1px solid #e5e7eb',
              display: 'flex', alignItems: 'flex-start', gap: 1.5,
            }}>
              <Box sx={{
                width: 40, height: 40, borderRadius: 2,
                bgcolor: `${s.color}14`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: s.color, flexShrink: 0,
              }}>
                {s.icon}
              </Box>
              <Box>
                <Typography variant="caption" sx={{ color: 'text.secondary', fontSize: '0.68rem', display: 'block' }}>
                  {s.label}
                </Typography>
                <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2, fontSize: '1.25rem' }}>
                  {s.value}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.25, mt: 0.25 }}>
                  {s.trend === 'up' && <TrendingUpIcon sx={{ fontSize: 12, color: '#16A34A' }} />}
                  {s.trend === 'down' && <TrendingDownIcon sx={{ fontSize: 12, color: '#16A34A' }} />}
                  <Typography variant="caption" sx={{ fontSize: '0.6rem', color: 'text.secondary' }}>
                    {s.sub}
                  </Typography>
                </Box>
              </Box>
            </Paper>
          ))}
        </Box>

        <ChatPanel messages={messages} isLoading={isLoading} onSend={handleSend} />
      </Box>
    </Box>
  )
}
