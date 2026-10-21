import { Bookmark } from '../model/Bookmark';

export function deepLinkOf(id: string): string {
  return `flowpage://bookmark/${id}`;
}

export function shareContentOf(bookmark: Bookmark): string {
  return bookmark.url.trim().length > 0 ? bookmark.url : deepLinkOf(bookmark.id);
}

export function deepLinkTextOf(bookmark: Bookmark): string {
  const link = deepLinkOf(bookmark.id);
  const title = bookmark.title.trim();
  return title.length > 0 ? `${title} ${link}` : link;
}
