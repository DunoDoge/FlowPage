function looksEscaped(input: string): boolean {
  return input.indexOf('\\u003C') >= 0 || input.indexOf('\\u003E') >= 0;
}

function isHexDigit(ch: string): boolean {
  return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
}

function hexCodeAt(input: string, start: number): number {
  if (start + 4 > input.length) {
    return -1;
  }
  for (let i = 0; i < 4; i++) {
    if (!isHexDigit(input.charAt(start + i))) {
      return -1;
    }
  }
  const code = parseInt(input.substring(start, start + 4), 16);
  return isNaN(code) ? -1 : code;
}

export function decodeWebHtml(input: string): string {
  if (input.length === 0 || !looksEscaped(input)) {
    return input;
  }
  let plain = '';
  let index = 0;
  while (index < input.length) {
    const ch = input.charAt(index);
    if (ch !== '\\' || index + 1 >= input.length) {
      plain = `${plain}${ch}`;
      index = index + 1;
      continue;
    }
    const next = input.charAt(index + 1);
    if (next === 'u') {
      const code = hexCodeAt(input, index + 2);
      if (code >= 0) {
        plain = `${plain}${String.fromCharCode(code)}`;
        index = index + 6;
        continue;
      }
    }
    if (next === '"' || next === '\\' || next === '/' || next === '\'') {
      plain = `${plain}${next}`;
      index = index + 2;
      continue;
    }
    plain = `${plain}${ch}`;
    index = index + 1;
  }
  return plain;
}
