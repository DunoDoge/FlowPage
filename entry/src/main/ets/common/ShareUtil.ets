import { Bookmark } from '../model/Bookmark';

// App Linking host (AGC-published; module.json5 skills must keep the same
// host) and the /s redirect path backed by the domain server. Wrapped links
// open FlowPage's reading layer on devices with the app installed and 302 to
// the original URL everywhere else.
export const SHARE_LINK_HOST: string = 'dunodoge.com';
export const SHARE_LINK_PREFIX: string = `https://${SHARE_LINK_HOST}/s?u=`;

export function shareLinkOf(url: string): string {
  return `${SHARE_LINK_PREFIX}${encodeURIComponent(url)}`;
}

// Returns the wrapped-around URL for an incoming App Linking share link, or
// '' when the link is not ours (host/path mismatch, missing u).
export function shareLinkTargetOf(uri: string): string {
  if (!uri.startsWith(SHARE_LINK_PREFIX)) {
    return '';
  }
  return decodeURIComponent(uri.substring(SHARE_LINK_PREFIX.length));
}

export function deepLinkOf(id: string): string {
  return `flowpage://bookmark/${id}`;
}

export function deepLinkTextOf(bookmark: Bookmark): string {
  const link = deepLinkOf(bookmark.id);
  const title = bookmark.title.trim();
  return title.length > 0 ? `${title} ${link}` : link;
}
