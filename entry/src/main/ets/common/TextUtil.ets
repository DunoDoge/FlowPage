export function splitIntoChunks(text: string, maxChars: number): string[] {
  const chunks: string[] = [];
  const limit = maxChars > 0 ? maxChars : 4000;
  const paragraphs = text.split('\n');
  let current = '';
  for (let i = 0; i < paragraphs.length; i++) {
    const paragraph = paragraphs[i];
    if (paragraph.length === 0) {
      continue;
    }
    if (paragraph.length > limit) {
      if (current.length > 0) {
        chunks.push(current);
        current = '';
      }
      let start = 0;
      while (start < paragraph.length) {
        const end = start + limit < paragraph.length ? start + limit : paragraph.length;
        chunks.push(paragraph.substring(start, end));
        start = end;
      }
      continue;
    }
    const candidate = current.length === 0 ? paragraph : `${current}\n${paragraph}`;
    if (candidate.length > limit) {
      chunks.push(current);
      current = paragraph;
    } else {
      current = candidate;
    }
  }
  if (current.length > 0) {
    chunks.push(current);
  }
  return chunks;
}
