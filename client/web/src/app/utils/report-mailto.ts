import { ChatMessage, ChatMessageType } from './constants';

const MAX_REPORTED_TEXT = 1000;
const MAX_FILENAME = 200;

export function buildReportMailto(
  supportEmail: string,
  subject: string,
  intro: string,
  message: ChatMessage,
  isPrivateRoom: boolean,
  appVersion: string
): string {
  const lines = [
    intro,
    '',
    '',
    '',
    '---',
    `App: ${appVersion} (web)`,
    `Browser: ${typeof navigator === 'undefined' ? 'unknown' : navigator.userAgent}`,
    `Room: ${isPrivateRoom ? 'Private session' : 'Public room'}`,
    '',
  ];

  if (message.type === ChatMessageType.ATTACHMENT && message.fileTransfer) {
    lines.push(`Reported file: ${truncate(message.fileTransfer.fileName, MAX_FILENAME)}`);
  } else {
    lines.push('Reported message:');
    lines.push(truncate(message.text, MAX_REPORTED_TEXT));
  }

  const body = lines.join('\n');
  return `mailto:${supportEmail}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function truncate(text: string, limit: number): string {
  return text.length <= limit ? text : `${text.slice(0, limit)}…`;
}
