#!/usr/bin/env node
/**
 * WhatsApp Notification Module for Clawdbot
 * Supports both Twilio and CallMeBot providers
 */

import https from 'https';
import { URL, URLSearchParams } from 'url';

// Load environment
const env = process.env;

/**
 * Send WhatsApp message via Twilio
 */
async function sendViaTwilio(message) {
  const accountSid = env.TWILIO_ACCOUNT_SID;
  const authToken = env.TWILIO_AUTH_TOKEN;
  const from = env.TWILIO_WHATSAPP_FROM || 'whatsapp:+14155238886';
  const to = env.NOTIFY_WHATSAPP_TO;

  if (!accountSid || !authToken || !to) {
    throw new Error('Twilio credentials not configured');
  }

  const data = new URLSearchParams({
    Body: message,
    From: from,
    To: to
  }).toString();

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.twilio.com',
      port: 443,
      path: `/2010-04-01/Accounts/${accountSid}/Messages.json`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(data),
        'Authorization': 'Basic ' + Buffer.from(`${accountSid}:${authToken}`).toString('base64')
      }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(body));
        } else {
          reject(new Error(`Twilio error: ${res.statusCode} - ${body}`));
        }
      });
    });

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

/**
 * Send WhatsApp message via CallMeBot (free)
 */
async function sendViaCallMeBot(message) {
  const phone = env.CALLMEBOT_PHONE;
  const apikey = env.CALLMEBOT_APIKEY;

  if (!phone || !apikey) {
    throw new Error('CallMeBot credentials not configured');
  }

  const params = new URLSearchParams({
    phone: phone,
    text: message,
    apikey: apikey
  });

  return new Promise((resolve, reject) => {
    const url = new URL(`https://api.callmebot.com/whatsapp.php?${params}`);

    https.get(url, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({ success: true, response: body });
        } else {
          reject(new Error(`CallMeBot error: ${res.statusCode} - ${body}`));
        }
      });
    }).on('error', reject);
  });
}

/**
 * Send WhatsApp message (auto-selects provider)
 */
export async function sendWhatsApp(message) {
  // Try Twilio first (more reliable)
  if (env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN) {
    try {
      return await sendViaTwilio(message);
    } catch (err) {
      console.error('Twilio failed:', err.message);
    }
  }

  // Fall back to CallMeBot
  if (env.CALLMEBOT_PHONE && env.CALLMEBOT_APIKEY) {
    try {
      return await sendViaCallMeBot(message);
    } catch (err) {
      console.error('CallMeBot failed:', err.message);
    }
  }

  throw new Error('No WhatsApp provider configured or all providers failed');
}

// CLI interface
if (process.argv[1] === import.meta.url.replace('file://', '') ||
    process.argv[1].endsWith('whatsapp.js')) {

  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
WhatsApp Notification for Clawdbot

Usage: node whatsapp.js [options] <message>

Options:
  --provider twilio|callmebot    Force specific provider
  -h, --help                     Show this help

Environment:
  TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM, NOTIFY_WHATSAPP_TO
  CALLMEBOT_PHONE, CALLMEBOT_APIKEY

Examples:
  node whatsapp.js "Hello from Clawdbot!"
  node whatsapp.js --provider twilio "Task complete"
`);
    process.exit(0);
  }

  // Parse message from args
  const message = args.filter(a => !a.startsWith('--')).join(' ');

  if (!message) {
    console.error('Error: Message is required');
    process.exit(1);
  }

  sendWhatsApp(message)
    .then(() => {
      console.log('WhatsApp message sent successfully');
      process.exit(0);
    })
    .catch(err => {
      console.error('Failed to send WhatsApp:', err.message);
      process.exit(1);
    });
}

export default { sendWhatsApp, sendViaTwilio, sendViaCallMeBot };
