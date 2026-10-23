import { ArticleLink } from '../model/Article';

export class ReaderSegment {
  text: string = '';
  url: string = '';
  matched: boolean = false;
}

class MatchRange {
  start: number = 0;
  end: number = 0;

  static of(start: number, end: number): MatchRange {
    const range = new MatchRange();
    range.start = start;
    range.end = end;
    return range;
  }
}

function addCut(cuts: number[], value: number, length: number): void {
  if (value > 0 && value < length) {
    cuts.push(value);
  }
}

function segmentOf(text: string, start: number, end: number, url: string, matched: boolean): ReaderSegment {
  const segment = new ReaderSegment();
  segment.text = text.substring(start, end);
  segment.url = url;
  segment.matched = matched;
  return segment;
}

export function readerSegments(text: string, links: ArticleLink[], keyword: string): ReaderSegment[] {
  const segments: ReaderSegment[] = [];
  if (text.length === 0) {
    return segments;
  }
  const needle = keyword.trim().toLowerCase();
  const matches: MatchRange[] = [];
  if (needle.length > 0) {
    const lower = text.toLowerCase();
    let index = 0;
    while (index < text.length) {
      const found = lower.indexOf(needle, index);
      if (found < 0) {
        break;
      }
      matches.push(MatchRange.of(found, found + needle.length));
      index = found + needle.length;
    }
  }
  if (links.length === 0 && matches.length === 0) {
    const whole = new ReaderSegment();
    whole.text = text;
    segments.push(whole);
    return segments;
  }

  const cuts: number[] = [0, text.length];
  for (let i = 0; i < links.length; i++) {
    addCut(cuts, links[i].start, text.length);
    addCut(cuts, links[i].end, text.length);
  }
  for (let i = 0; i < matches.length; i++) {
    addCut(cuts, matches[i].start, text.length);
    addCut(cuts, matches[i].end, text.length);
  }
  cuts.sort((a: number, b: number): number => a - b);
  const unique: number[] = [];
  for (let i = 0; i < cuts.length; i++) {
    if (unique.length === 0 || unique[unique.length - 1] !== cuts[i]) {
      unique.push(cuts[i]);
    }
  }

  let linkCursor = 0;
  let matchCursor = 0;
  for (let i = 0; i + 1 < unique.length; i++) {
    const start = unique[i];
    const end = unique[i + 1];
    if (end <= start) {
      continue;
    }
    while (linkCursor < links.length && links[linkCursor].end <= start) {
      linkCursor = linkCursor + 1;
    }
    while (matchCursor < matches.length && matches[matchCursor].end <= start) {
      matchCursor = matchCursor + 1;
    }
    let url = '';
    if (linkCursor < links.length) {
      const link = links[linkCursor];
      if (link.start <= start && link.end >= end) {
        url = link.url;
      }
    }
    let matched = false;
    if (matchCursor < matches.length) {
      const match = matches[matchCursor];
      if (match.start <= start && match.end >= end) {
        matched = true;
      }
    }
    const segment = segmentOf(text, start, end, url, matched);
    const last = segments.length > 0 ? segments[segments.length - 1] : undefined;
    if (last !== undefined && last.url === url && last.matched === matched) {
      last.text = last.text + segment.text;
    } else {
      segments.push(segment);
    }
  }
  return segments;
}
