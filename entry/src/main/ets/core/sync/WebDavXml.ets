import { RemoteItem } from './RemoteItem';

export class WebDavXml {
  static decodeEntities(value: string): string {
    let text = value;
    text = text.replace(new RegExp('&amp;', 'g'), '&');
    text = text.replace(new RegExp('&lt;', 'g'), '<');
    text = text.replace(new RegExp('&gt;', 'g'), '>');
    text = text.replace(new RegExp('&quot;', 'g'), '"');
    return text;
  }

  static parseEtag(xml: string): string {
    const match = new RegExp('<[^>]*getetag[^>]*>([^<]*)<', 'i').exec(xml);
    if (match === null) {
      return '';
    }
    return WebDavXml.decodeEntities(match[1].trim());
  }

  static parseItems(xml: string): RemoteItem[] {
    const items: RemoteItem[] = [];
    const blocks = xml.match(new RegExp('<[^>]*response[^>]*>[\\s\\S]*?</[^>]*response>', 'gi'));
    if (blocks === null) {
      return items;
    }
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      const hrefMatch = new RegExp('<[^>]*href[^>]*>([^<]*)<', 'i').exec(block);
      if (hrefMatch === null) {
        continue;
      }
      let href = WebDavXml.decodeEntities(hrefMatch[1].trim());
      if (href.endsWith('/')) {
        continue;
      }
      const noQuery = href.split('?')[0];
      const segments = noQuery.split('/');
      let name = segments[segments.length - 1];
      name = name.replace(new RegExp('%20', 'g'), ' ');
      try {
        name = decodeURIComponent(name);
      } catch (error) {
        continue;
      }
      if (!name.endsWith('.json')) {
        continue;
      }
      const item = new RemoteItem();
      item.name = name.substring(0, name.length - 5);
      item.etag = WebDavXml.parseEtag(block);
      items.push(item);
    }
    return items;
  }
}
