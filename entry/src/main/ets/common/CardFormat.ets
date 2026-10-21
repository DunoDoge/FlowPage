// Printable ASCII so the preferences XML file stays valid; encoded fields can never contain it.
export const CARD_FIELD_SEPARATOR: string = '%01';

export class CardLine {
  title: string = '';
  domain: string = '';
  id: string = '';
}

export function cardTitleOf(title: string): string {
  let result = '';
  for (let i = 0; i < title.length; i++) {
    const code = title.charCodeAt(i);
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) {
      result += ' ';
    } else {
      result += title.charAt(i);
    }
  }
  return result;
}

function decodeField(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

export function cardLineOf(title: string, domain: string, id: string): string {
  return `${encodeURIComponent(cardTitleOf(title))}${CARD_FIELD_SEPARATOR}` +
    `${encodeURIComponent(domain)}${CARD_FIELD_SEPARATOR}${encodeURIComponent(id)}`;
}

export function parseCardLine(line: string): CardLine | undefined {
  const parts = line.split(CARD_FIELD_SEPARATOR);
  if (parts.length < 3) {
    return undefined;
  }
  const item = new CardLine();
  item.title = decodeField(parts[0]);
  item.domain = decodeField(parts[1]);
  item.id = decodeField(parts[2]);
  return item;
}

export function parseCardLines(raw: string): CardLine[] {
  const items: CardLine[] = [];
  if (raw.length === 0) {
    return items;
  }
  const lines = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const item = parseCardLine(lines[i]);
    if (item !== undefined) {
      items.push(item);
    }
  }
  return items;
}
