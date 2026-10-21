export class HighlightSegment {
  text: string = '';
  matched: boolean = false;
}

export function highlightSegments(text: string, keyword: string): HighlightSegment[] {
  const segments: HighlightSegment[] = [];
  const needle = keyword.trim().toLowerCase();
  if (text.length === 0) {
    return segments;
  }
  if (needle.length === 0) {
    const whole = new HighlightSegment();
    whole.text = text;
    segments.push(whole);
    return segments;
  }
  const lower = text.toLowerCase();
  let index = 0;
  while (index < text.length) {
    const found = lower.indexOf(needle, index);
    if (found < 0) {
      const rest = new HighlightSegment();
      rest.text = text.substring(index);
      segments.push(rest);
      break;
    }
    if (found > index) {
      const before = new HighlightSegment();
      before.text = text.substring(index, found);
      segments.push(before);
    }
    const match = new HighlightSegment();
    match.text = text.substring(found, found + needle.length);
    match.matched = true;
    segments.push(match);
    index = found + needle.length;
  }
  return segments;
}
