import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const CHUNK: number = 262144;

// Reads a URI-granted text file in full. The URI grant is scoped to the
// sharing session / open-with want, so callers must invoke this before that
// scope ends and stash the decoded text, never the URI.
export async function readTextFileAll(
  uri: string,
  onProgress?: (percent: number) => void
): Promise<string> {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat = fs.statSync(file.fd);
    const total = stat.size;
    const bytes = new Uint8Array(total);
    const buffer = new ArrayBuffer(CHUNK);
    let offset = 0;
    while (offset < total) {
      const remaining = total - offset;
      const toRead = remaining < CHUNK ? remaining : CHUNK;
      const read = await fs.read(file.fd, buffer, { offset: offset, length: toRead });
      if (read <= 0) {
        break;
      }
      bytes.set(new Uint8Array(buffer.slice(0, read)), offset);
      offset = offset + read;
      if (onProgress !== undefined) {
        onProgress(Math.floor(offset * 100 / total));
      }
    }
    return new util.TextDecoder('utf-8').decodeToString(bytes.subarray(0, offset));
  } finally {
    fs.closeSync(file);
  }
}
