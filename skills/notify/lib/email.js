#!/usr/bin/env node
/**
 * Email Notification Module for Clawdbot
 * Uses SendGrid for email delivery
 */

import https from 'https';

// Load environment
const env = process.env;

/**
 * Send email via SendGrid
 */
export async function sendEmail(subject, body, options = {}) {
  const apiKey = env.SENDGRID_API_KEY;
  const to = options.to || env.NOTIFY_EMAIL_TO;
  const from = options.from || env.NOTIFY_EMAIL_FROM || 'clawdbot@noreply.local';

  if (!apiKey) {
    throw new Error('SENDGRID_API_KEY not configured');
  }

  if (!to) {
    throw new Error('Recipient email not configured (NOTIFY_EMAIL_TO)');
  }

  const payload = JSON.stringify({
    personalizations: [
      {
        to: [{ email: to }],
        subject: subject
      }
    ],
    from: { email: from, name: 'Clawdbot' },
    content: [
      {
        type: 'text/plain',
        value: body
      }
    ]
  });

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.sendgrid.com',
      port: 443,
      path: '/v3/mail/send',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'Authorization': `Bearer ${apiKey}`
      }
    };

    const req = https.request(options, (res) => {
      let responseBody = '';
      res.on('data', chunk => responseBody += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({ success: true, statusCode: res.statusCode });
        } else {
          reject(new Error(`SendGrid error: ${res.statusCode} - ${responseBody}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

/**
 * Send HTML email via SendGrid
 */
export async function sendHtmlEmail(subject, html, plainText, options = {}) {
  const apiKey = env.SENDGRID_API_KEY;
  const to = options.to || env.NOTIFY_EMAIL_TO;
  const from = options.from || env.NOTIFY_EMAIL_FROM || 'clawdbot@noreply.local';

  if (!apiKey || !to) {
    throw new Error('SendGrid credentials or recipient not configured');
  }

  const content = [
    { type: 'text/plain', value: plainText || html.replace(/<[^>]*>/g, '') }
  ];

  if (html) {
    content.push({ type: 'text/html', value: html });
  }

  const payload = JSON.stringify({
    personalizations: [
      {
        to: [{ email: to }],
        subject: subject
      }
    ],
    from: { email: from, name: 'Clawdbot' },
    content: content
  });

  return new Promise((resolve, reject) => {
    const reqOptions = {
      hostname: 'api.sendgrid.com',
      port: 443,
      path: '/v3/mail/send',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'Authorization': `Bearer ${apiKey}`
      }
    };

    const req = https.request(reqOptions, (res) => {
      let responseBody = '';
      res.on('data', chunk => responseBody += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({ success: true, statusCode: res.statusCode });
        } else {
          reject(new Error(`SendGrid error: ${res.statusCode} - ${responseBody}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

// CLI interface
if (process.argv[1] === import.meta.url.replace('file://', '') ||
    process.argv[1].endsWith('email.js')) {

  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
Email Notification for Clawdbot

Usage: node email.js [options]

Options:
  --to EMAIL          Recipient email
  --from EMAIL        Sender email
  --subject TEXT      Email subject
  --body TEXT         Email body
  -h, --help          Show this help

Environment:
  SENDGRID_API_KEY    SendGrid API key (required)
  NOTIFY_EMAIL_TO     Default recipient
  NOTIFY_EMAIL_FROM   Default sender

Examples:
  node email.js --subject "Task Complete" --body "Your task is done!"
  node email.js --to user@example.com --subject "Alert" --body "Check PR"
`);
    process.exit(0);
  }

  // Parse arguments
  const getArg = (name) => {
    const idx = args.indexOf(name);
    return idx !== -1 && args[idx + 1] ? args[idx + 1] : null;
  };

  const to = getArg('--to');
  const from = getArg('--from');
  const subject = getArg('--subject');
  const body = getArg('--body');

  if (!subject || !body) {
    console.error('Error: --subject and --body are required');
    process.exit(1);
  }

  sendEmail(subject, body, { to, from })
    .then(() => {
      console.log('Email sent successfully');
      process.exit(0);
    })
    .catch(err => {
      console.error('Failed to send email:', err.message);
      process.exit(1);
    });
}

export default { sendEmail, sendHtmlEmail };
