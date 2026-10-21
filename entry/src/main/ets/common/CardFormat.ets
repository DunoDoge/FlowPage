export const CARD_FIELD_SEPARATOR: string = '\u0001';

export class CardLine {
  title: string = '';
  domain: string = '';
  id: string = '';
}

export function cardTitleOf(title: string): string {
  return title
    .split('\r').join(' ')
    .split('\n').join(' ')
    .split(CARD_FIELD_SEPARATOR).join(' ');
}

export function cardLineOf(title: string, domain: string, id: string): string {
  return `${cardTitleOf(title)}${CARD_FIELD_SEPARATOR}${domain}${CARD_FIELD_SEPARATOR}${id}`;
}

export function parseCardLine(line: string): CardLine | undefined {
  const parts = line.split(CARD_FIELD_SEPARATOR);
  if (parts.length < 3) {
    return undefined;
  }
  const item = new CardLine();
  item.title = parts[0];
  item.domain = parts[1];
  item.id = parts[2];
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
