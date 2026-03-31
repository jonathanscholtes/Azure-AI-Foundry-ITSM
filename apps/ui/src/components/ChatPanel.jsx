import { useState, useRef, useEffect } from 'react'
import {
  Box, Paper, Typography, TextField, IconButton,
  Avatar, CircularProgress, Chip, Grid, Card, CardActionArea,
} from '@mui/material'
import SendIcon from '@mui/icons-material/Send'
import SmartToyOutlinedIcon from '@mui/icons-material/SmartToyOutlined'
import PersonIcon from '@mui/icons-material/Person'
import BugReportIcon from '@mui/icons-material/BugReport'
import ConfirmationNumberIcon from '@mui/icons-material/ConfirmationNumber'
import SearchIcon from '@mui/icons-material/ManageSearch'
import ReactMarkdown from 'react-markdown'

const AGENT_LABELS = {
  classifier: 'Classifier',
  kb_lookup:  'KB Lookup',
  ticket:     'Tickets',
  triage:     'Triage',
  error:      'Error',
}

const QUICK_ACTIONS = [
  {
    icon: <SearchIcon />,
    label: 'Search KB',
    description: 'Find solutions in the knowledge base',
    color: '#0078D4',
    prompt: 'How do I reset my corporate password?',
  },
  {
    icon: <ConfirmationNumberIcon />,
    label: 'Create Ticket',
    description: 'Submit a new support request',
    color: '#8764B8',
    prompt: 'I need to create a ticket - my Outlook is not syncing emails on my phone',
  },
  {
    icon: <BugReportIcon />,
    label: 'Triage Issue',
    description: 'Diagnose and troubleshoot problems',
    color: '#F59E0B',
    prompt: 'My laptop is running very slow and applications keep freezing. Help me troubleshoot.',
  },
]

function MessageBubble({ msg }) {
  const isUser = msg.role === 'user'
  const isError = msg.agent === 'error'
  const agentLabel = AGENT_LABELS[msg.agent] || msg.agent || ''

  return (
    <Box sx={{
      display: 'flex',
      gap: 1.5,
      mb: 2,
      flexDirection: isUser ? 'row-reverse' : 'row',
      alignItems: 'flex-start',
    }}>
      <Avatar sx={{
        width: 32, height: 32,
        bgcolor: isUser ? 'primary.main' : isError ? 'error.main' : 'grey.700',
        flexShrink: 0,
      }}>
        {isUser
          ? <PersonIcon sx={{ fontSize: 18 }} />
          : <SmartToyOutlinedIcon sx={{ fontSize: 18 }} />
        }
      </Avatar>
      <Box sx={{ maxWidth: '75%', minWidth: 0 }}>
        {!isUser && agentLabel && (
          <Chip
            label={agentLabel}
            size="small"
            sx={{
              mb: 0.5,
              height: 18,
              fontSize: '0.6rem',
              fontWeight: 600,
              bgcolor: isError ? 'error.50' : 'grey.100',
              color: isError ? 'error.main' : 'text.secondary',
            }}
          />
        )}
        <Paper
          elevation={0}
          sx={{
            p: 2,
            bgcolor: isUser ? 'primary.main' : isError ? 'error.50' : 'grey.50',
            color: isUser ? '#fff' : 'text.primary',
            borderRadius: 2,
            border: isError ? '1px solid' : 'none',
            borderColor: isError ? 'error.light' : 'transparent',
            '& p': { m: 0, lineHeight: 1.6 },
            '& p + p': { mt: 1 },
            '& code': {
              bgcolor: isUser ? 'rgba(255,255,255,0.15)' : 'grey.200',
              px: 0.5,
              borderRadius: 0.5,
              fontSize: '0.85em',
            },
            '& pre': {
              bgcolor: isUser ? 'rgba(0,0,0,0.2)' : 'grey.200',
              p: 1.5,
              borderRadius: 1,
              overflow: 'auto',
              '& code': { bgcolor: 'transparent', p: 0 },
            },
            '& ul, & ol': { pl: 2.5, my: 0.5 },
            '& li': { mb: 0.25 },
          }}
        >
          {isUser ? (
            <Typography variant="body2">{msg.text}</Typography>
          ) : (
            <ReactMarkdown>{msg.text || '...'}</ReactMarkdown>
          )}
        </Paper>
      </Box>
    </Box>
  )
}

export default function ChatPanel({ messages, isLoading, onSend }) {
  const [input, setInput] = useState('')
  const scrollRef = useRef(null)

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [messages])

  function handleSubmit(e) {
    e.preventDefault()
    const text = input.trim()
    if (!text || isLoading) return
    setInput('')
    onSend(text)
  }

  return (
    <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>

      {/* Messages area */}
      <Box
        ref={scrollRef}
        sx={{ flexGrow: 1, overflow: 'auto', p: { xs: 2, md: 3 } }}
      >
        {messages.length === 0 && (
          <Box sx={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', height: '100%',
          }}>
            <SmartToyOutlinedIcon sx={{ fontSize: 48, color: 'primary.main', mb: 1.5, opacity: 0.6 }} />
            <Typography variant="h6" color="text.primary" fontWeight={700} gutterBottom>
              How can I help you today?
            </Typography>
            <Typography variant="body2" color="text.secondary" align="center" sx={{ maxWidth: 460, mb: 3.5 }}>
              I can search the knowledge base, create and manage support tickets,
              or help triage IT issues. Choose a quick action or type your own request.
            </Typography>

            <Typography variant="overline" sx={{
              fontWeight: 600, letterSpacing: '0.1em',
              color: 'text.secondary', mb: 1.5, fontSize: '0.62rem',
            }}>
              Quick Actions
            </Typography>

            <Grid container spacing={2} sx={{ maxWidth: 540 }}>
              {QUICK_ACTIONS.map((action) => (
                <Grid item xs={4} key={action.label}>
                  <Card variant="outlined" sx={{
                    borderRadius: 2.5,
                    transition: 'all 0.2s',
                    height: '100%',
                    '&:hover': {
                      borderColor: 'primary.main',
                      boxShadow: '0 2px 12px rgba(0,120,212,0.12)',
                      transform: 'translateY(-2px)',
                    },
                  }}>
                    <CardActionArea
                      onClick={() => { setInput(''); onSend(action.prompt) }}
                      sx={{ p: 2, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1, height: '100%' }}
                    >
                      <Box sx={{
                        width: 44, height: 44, borderRadius: 2,
                        bgcolor: `${action.color}14`,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: action.color,
                      }}>
                        {action.icon}
                      </Box>
                      <Typography variant="body2" fontWeight={600} align="center">
                        {action.label}
                      </Typography>
                      <Typography variant="caption" color="text.secondary" align="center" sx={{ fontSize: '0.68rem', lineHeight: 1.3 }}>
                        {action.description}
                      </Typography>
                    </CardActionArea>
                  </Card>
                </Grid>
              ))}
            </Grid>
          </Box>
        )}

        {messages.map((msg, i) => (
          <MessageBubble key={i} msg={msg} />
        ))}

        {isLoading && messages.length > 0 && !messages[messages.length - 1]?.text && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, ml: 5.5, mb: 2 }}>
            <CircularProgress size={16} thickness={5} />
            <Typography variant="caption" color="text.secondary">
              Processing...
            </Typography>
          </Box>
        )}
      </Box>

      {/* Input bar */}
      <Paper
        component="form"
        onSubmit={handleSubmit}
        elevation={3}
        sx={{
          display: 'flex', alignItems: 'center', gap: 1,
          p: 1.5, m: { xs: 1, md: 2 }, mt: 0,
          borderRadius: 3,
        }}
      >
        <TextField
          fullWidth
          size="small"
          placeholder="Type your message..."
          variant="outlined"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          disabled={isLoading}
          autoFocus
          sx={{
            '& .MuiOutlinedInput-root': {
              borderRadius: 2,
              '& fieldset': { borderColor: 'grey.200' },
            },
          }}
        />
        <IconButton
          type="submit"
          color="primary"
          disabled={!input.trim() || isLoading}
          sx={{
            bgcolor: 'primary.main',
            color: '#fff',
            '&:hover': { bgcolor: 'primary.dark' },
            '&.Mui-disabled': { bgcolor: 'grey.200', color: 'grey.400' },
            width: 40, height: 40,
          }}
        >
          <SendIcon fontSize="small" />
        </IconButton>
      </Paper>
    </Box>
  )
}
