import { Chip } from '@mui/material'
import CheckCircleIcon from '@mui/icons-material/CheckCircle'
import CancelIcon from '@mui/icons-material/Cancel'
import WarningAmberIcon from '@mui/icons-material/WarningAmber'

export default function StatusChip({ status }) {
  if (status === 'done' || status === 'success') {
    return (
      <Chip
        icon={<CheckCircleIcon />}
        label="Done"
        color="success"
        size="small"
        variant="outlined"
      />
    )
  }

  if (status === 'error') {
    return (
      <Chip
        icon={<CancelIcon />}
        label="Error"
        color="error"
        size="small"
        variant="outlined"
      />
    )
  }

  if (status === 'running') {
    return (
      <Chip
        icon={<WarningAmberIcon />}
        label="Running"
        color="warning"
        size="small"
        variant="outlined"
      />
    )
  }

  return null
}
