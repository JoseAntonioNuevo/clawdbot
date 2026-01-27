---
name: notify
description: |
  Send notifications via WhatsApp, email, or Discord when tasks complete or fail.
  Use this skill to alert the user about orchestrator results.

  Triggers: "notify", "send message", "alert user", "tell me when done",
  "send notification", "message me"
metadata:
  clawdbot:
    requiredEnv:
      - NOTIFY_WHATSAPP_TO  # or CALLMEBOT_PHONE or SENDGRID_API_KEY
---

# Notification Skill

Send notifications when orchestration tasks complete or fail.

## Supported Channels

### 1. WhatsApp via Twilio (Recommended)

Best for immediate notifications. Requires Twilio account.

**Setup:**
1. Create account at https://console.twilio.com
2. Enable WhatsApp sandbox or get approved number
3. Configure environment:
```bash
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxx
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886
NOTIFY_WHATSAPP_TO=whatsapp:+1XXXXXXXXXX
```

### 2. WhatsApp via CallMeBot (Free)

Free alternative, simpler setup but less reliable.

**Setup:**
1. Send "I allow callmebot to send me messages" to +34 644 51 95 23 on WhatsApp
2. Get your API key from the response
3. Configure environment:
```bash
CALLMEBOT_PHONE=+1XXXXXXXXXX
CALLMEBOT_APIKEY=xxxxxxx
```

### 3. Email via SendGrid

For email notifications. Good for detailed reports.

**Setup:**
1. Create account at https://sendgrid.com
2. Generate API key
3. Configure environment:
```bash
SENDGRID_API_KEY=SG.xxxxxxxxxxxx
NOTIFY_EMAIL_TO=your@email.com
NOTIFY_EMAIL_FROM=clawdbot@yourdomain.com
```

## Usage

### From Shell

```bash
# Success notification
./lib/notify.sh success "Task description" "https://github.com/user/repo/pull/123" /path/to/state.json

# Failure notification
./lib/notify.sh failure "Task description" /path/to/failure_report.md /path/to/state.json

# Progress notification
./lib/notify.sh progress "Task description" "Iteration 42/80" /path/to/state.json
```

### From JavaScript

```javascript
import { sendWhatsApp } from './lib/whatsapp.js';
import { sendEmail } from './lib/email.js';

// WhatsApp
await sendWhatsApp('🦞 Task complete! PR: https://github.com/...');

// Email
await sendEmail(
  'Task Complete',
  'Your coding task has been completed...'
);
```

## Message Templates

### Success Message
```
🦞 CLAWDBOT TASK COMPLETE

✅ Task: <task_description>
📁 Project: <project_name>
🔀 PR: <pr_url>

Iterations: <N> (OpenCode) / <M> (Claude)
Status: Codex Approved ✓

View PR: <url>
```

### Failure Message
```
🦞 CLAWDBOT TASK FAILED

❌ Task: <task_description>
📁 Project: <project_name>
🔀 Branch: <branch_name>

Iterations: 80 (OpenCode) + 10 (Claude)
Status: Could not resolve Codex issues

Blocking Issues:
- <issue 1>
- <issue 2>

Logs: <log_path>
Worktree: <worktree_path>

Manual review required.
```

### Progress Message (Optional)
```
🦞 CLAWDBOT PROGRESS

📁 Project: <project_name>
🔄 Task: <task_description>

Current iteration: <N>
Status: <current_status>
```

## Configuration

In `~/.clawdbot-orchestrator.env`:

```bash
# Notification preferences
NOTIFY_ON_SUCCESS=true
NOTIFY_ON_FAILURE=true
NOTIFY_PROGRESS_INTERVAL=0  # 0 = disabled, N = every N iterations

# Preferred channel (whatsapp, email)
NOTIFY_PREFERRED_CHANNEL=whatsapp
```

## Error Handling

If notification fails:
1. Log the error
2. Continue execution (don't block on notification failures)
3. Print the message to stdout as fallback
4. Retry once after 5 seconds for transient failures

## Rate Limiting

- WhatsApp (Twilio): 1 message/second
- WhatsApp (CallMeBot): 1 message/25 seconds
- Email (SendGrid): Based on plan limits

The skill automatically respects these limits.
