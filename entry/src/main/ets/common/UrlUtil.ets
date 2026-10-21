import { url } from '@kit.ArkTS';

function hasScheme(text: string): boolean {
  return new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://').test(text);
}

function isTrackingParam(key: string): boolean {
  const lower = key.toLowerCase();
  if (lower.startsWith('utm_')) {
    return true;
  }
  const list: string[] = [
    'spm', 'from', 'source', 'share_source', 'share_from', 'fbclid',
    'gclid', 'yclid', 'mc_cid', 'mc_eid', 'ref', 'referrer', 's_cid'
  ];
  return list.indexOf(lower) >= 0;
}

export function normalizeUrl(input: string): string {
  const text = input.trim();
  if (text.length === 0) {
    return '';
  }
  const withScheme = hasScheme(text) ? text : `https://${text}`;
  try {
    const parsed = new url.URL(withScheme);
    const protocol = parsed.protocol.toLowerCase();
    if (protocol !== 'http:' && protocol !== 'https:') {
      return '';
    }
    const host = parsed.hostname.toLowerCase();
    if (host.length === 0) {
      return '';
    }
    const port = parsed.port;
    const path = parsed.pathname.length > 0 ? parsed.pathname : '/';
    const pairs: string[] = [];
    parsed.searchParams.forEach((value: string, key: string) => {
      if (!isTrackingParam(key)) {
        pairs.push(`${key}=${value}`);
      }
    });
    pairs.sort();
    const query = pairs.length > 0 ? `?${pairs.join('&')}` : '';
    const portPart = port.length > 0 ? `:${port}` : '';
    return `${protocol}//${host}${portPart}${path}${query}`;
  } catch (error) {
    return '';
  }
}

export function domainOf(input: string): string {
  const normalized = normalizeUrl(input);
  if (normalized.length === 0) {
    return '';
  }
  try {
    const parsed = new url.URL(normalized);
    const host = parsed.hostname.toLowerCase();
    if (host.startsWith('www.')) {
      return host.substring(4);
    }
    return host;
  } catch (error) {
    return '';
  }
}

export function extractFirstUrl(text: string): string {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const withScheme = new RegExp('https?://[^\\s<>"\']+', 'i');
  const match = withScheme.exec(trimmed);
  if (match !== null && match.length > 0) {
    return trimPunctuation(match[0]);
  }
  const bare = new RegExp('(?:[a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,}(?:/[^\\s<>"\']*)?', 'i');
  const bareMatch = bare.exec(trimmed);
  if (bareMatch !== null && bareMatch.length > 0) {
    return trimPunctuation(`https://${bareMatch[0]}`);
  }
  return '';
}

function trimPunctuation(value: string): string {
  let result = value;
  while (result.length > 0) {
    const last = result.charAt(result.length - 1);
    if (last === '.' || last === ',' || last === ';' || last === ')' ||
      last === ']' || last === '}' || last === '，' || last === '。') {
      result = result.substring(0, result.length - 1);
    } else {
      break;
    }
  }
  return result;
}

export function isValidHttpUrl(value: string): boolean {
  return normalizeUrl(value).length > 0;
}

export function fallbackTitle(input: string): string {
  const domain = domainOf(input);
  return domain.length > 0 ? domain : '未命名';
}

export function isSameUrl(first: string, second: string): boolean {
  const a = normalizeUrl(first);
  const b = normalizeUrl(second);
  return a.length > 0 && a === b;
}
