import {
  Box, Drawer, Typography, Divider, List, ListItemButton,
  ListItemIcon, ListItemText, Avatar, Badge, Tooltip,
} from '@mui/material'
import DashboardOutlinedIcon from '@mui/icons-material/DashboardOutlined'
import SmartToyOutlinedIcon from '@mui/icons-material/SmartToyOutlined'
import ConfirmationNumberOutlinedIcon from '@mui/icons-material/ConfirmationNumberOutlined'
import MenuBookOutlinedIcon from '@mui/icons-material/MenuBookOutlined'
import AssessmentOutlinedIcon from '@mui/icons-material/AssessmentOutlined'
import FiberManualRecordIcon from '@mui/icons-material/FiberManualRecord'

const SIDEBAR_WIDTH = 250

const NAV_ITEMS = [
  { key: 'dashboard',  label: 'Dashboard',           icon: <DashboardOutlinedIcon fontSize="small" /> },
  { key: 'assistant',  label: 'AI Assistant',         icon: <SmartToyOutlinedIcon fontSize="small" /> },
  { key: 'incidents',  label: 'Incidents',            icon: <ConfirmationNumberOutlinedIcon fontSize="small" />, badge: 42 },
  { key: 'kb',         label: 'Knowledge Base',       icon: <MenuBookOutlinedIcon fontSize="small" /> },
  { key: 'reports',    label: 'Reports & Analytics',  icon: <AssessmentOutlinedIcon fontSize="small" /> },
]

const AGENT_COLORS = {
  classifier: '#0078D4',
  kb_lookup:  '#00B7C3',
  ticket:     '#8764B8',
  triage:     '#F59E0B',
  error:      '#EF4444',
}

const sidebarStyles = {
  width: SIDEBAR_WIDTH,
  flexShrink: 0,
  '& .MuiDrawer-paper': {
    width: SIDEBAR_WIDTH,
    boxSizing: 'border-box',
    bgcolor: '#0f2027',
    borderRight: 'none',
    display: 'flex',
    flexDirection: 'column',
  },
}

export { SIDEBAR_WIDTH }

export default function Sidebar({ activityLog = [] }) {
  return (
    <Drawer variant="permanent" sx={sidebarStyles}>
      {/* Brand */}
      <Box sx={{ px: 2, py: 2, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Box sx={{
          width: 36, height: 36,
          bgcolor: 'primary.main',
          borderRadius: 2,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <SmartToyOutlinedIcon sx={{ fontSize: 20, color: '#fff' }} />
        </Box>
        <Box>
          <Typography variant="subtitle2" sx={{ color: '#fff', lineHeight: 1.2, fontSize: '0.88rem' }}>
            ITSM Desk
          </Typography>
          <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.4)', fontSize: '0.65rem' }}>
            Service Portal
          </Typography>
        </Box>
      </Box>

      <Divider sx={{ borderColor: 'rgba(255,255,255,0.06)' }} />

      {/* Navigation */}
      <Box sx={{ px: 1, pt: 1.5, pb: 0.5 }}>
        <Typography variant="overline" sx={{
          color: 'rgba(255,255,255,0.28)',
          fontWeight: 600,
          letterSpacing: '0.1em',
          fontSize: '0.6rem',
          px: 1,
          mb: 0.5,
          display: 'block',
        }}>
          Navigation
        </Typography>
        <List disablePadding>
          {NAV_ITEMS.map((item) => {
            const active = item.key === 'assistant'
            return (
              <Tooltip key={item.key} title={active ? '' : 'Coming in v2'} placement="right" arrow>
                <ListItemButton
                  disableRipple={!active}
                  sx={{
                    borderRadius: 1.5,
                    mb: 0.3,
                    py: 0.75,
                    px: 1.5,
                    borderLeft: active ? '3px solid #0078D4' : '3px solid transparent',
                    bgcolor: active ? 'rgba(0,120,212,0.15)' : 'transparent',
                    '&:hover': { bgcolor: active ? 'rgba(0,120,212,0.2)' : 'rgba(255,255,255,0.04)' },
                    cursor: active ? 'default' : 'default',
                  }}
                >
                  <ListItemIcon sx={{ minWidth: 34, color: active ? '#0078D4' : 'rgba(255,255,255,0.45)' }}>
                    {item.badge ? (
                      <Badge
                        badgeContent={item.badge}
                        color="error"
                        sx={{ '& .MuiBadge-badge': { fontSize: '0.55rem', height: 16, minWidth: 16, right: -4, top: -2 } }}
                      >
                        {item.icon}
                      </Badge>
                    ) : item.icon}
                  </ListItemIcon>
                  <ListItemText
                    primary={item.label}
                    primaryTypographyProps={{
                      fontSize: '0.8rem',
                      fontWeight: active ? 600 : 400,
                      color: active ? '#fff' : 'rgba(255,255,255,0.6)',
                    }}
                  />
                </ListItemButton>
              </Tooltip>
            )
          })}
        </List>
      </Box>

      <Divider sx={{ borderColor: 'rgba(255,255,255,0.06)', mx: 1 }} />

      {/* Activity Feed */}
      <Box sx={{ px: 2, pt: 1.5, flexGrow: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
        <Typography variant="overline" sx={{
          color: 'rgba(255,255,255,0.28)',
          fontWeight: 600,
          letterSpacing: '0.1em',
          fontSize: '0.6rem',
          mb: 1,
        }}>
          Live Activity
        </Typography>
        <Box sx={{
          flexGrow: 1, overflow: 'auto', minHeight: 0,
          '&::-webkit-scrollbar': { width: 3 },
          '&::-webkit-scrollbar-thumb': { bgcolor: 'rgba(255,255,255,0.08)', borderRadius: 2 },
        }}>
          {activityLog.length === 0 && (
            <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.18)', fontStyle: 'italic', display: 'block', mt: 0.5, fontSize: '0.7rem' }}>
              No recent activity
            </Typography>
          )}
          {activityLog.map((entry, i) => (
            <Box key={i} sx={{ display: 'flex', alignItems: 'flex-start', gap: 1, mb: 0.75 }}>
              <FiberManualRecordIcon sx={{
                fontSize: 7, mt: 0.55, flexShrink: 0,
                color: AGENT_COLORS[entry.agent] || 'rgba(255,255,255,0.25)',
              }} />
              <Box sx={{ minWidth: 0 }}>
                <Typography variant="caption" sx={{
                  color: 'rgba(255,255,255,0.65)',
                  display: 'block', lineHeight: 1.3, fontSize: '0.68rem',
                }} noWrap>
                  {entry.text}
                </Typography>
                <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.2)', fontSize: '0.58rem' }}>
                  {entry.ts}
                </Typography>
              </Box>
            </Box>
          ))}
        </Box>
      </Box>

      {/* User footer */}
      <Divider sx={{ borderColor: 'rgba(255,255,255,0.06)' }} />
      <Box sx={{ px: 2, py: 1.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Avatar sx={{ width: 32, height: 32, bgcolor: '#0078D4', fontSize: '0.7rem', fontWeight: 600 }}>
          JS
        </Avatar>
        <Box sx={{ minWidth: 0 }}>
          <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.8)', display: 'block', lineHeight: 1.2, fontSize: '0.72rem', fontWeight: 500 }} noWrap>
            Jonathan Scholtes
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            <FiberManualRecordIcon sx={{ fontSize: 6, color: '#16A34A' }} />
            <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.35)', fontSize: '0.6rem' }}>
              Online
            </Typography>
          </Box>
        </Box>
      </Box>
    </Drawer>
  )
}
