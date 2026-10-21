import { http } from '@kit.NetworkKit';
import { util, url } from '@kit.ArkTS';
import { Limits } from '../../common/Constants';
import { MetadataResult } from '../../model/MetadataResult';

export class MetadataService {
  private static decodeEntities(input: string): string {
    let text = input;
    const pairs: string[][] = [
      ['&amp;', '&'],
      ['&lt;', '<'],
      ['&gt;', '>'],
      ['&quot;', '"'],
      ['&#39;', '\''],
      ['&apos;', '\''],
      ['&nbsp;', ' ']
    ];
    for (let i = 0; i < pairs.length; i++) {
      text = text.replace(new RegExp(pairs[i][0], 'g'), pairs[i][1]);
    }
    return text;
  }

  static stripTags(html: string): string {
    let text = html;
    text = text.replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), ' ');
    text = text.replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), ' ');
    text = text.replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), ' ');
    text = text.replace(new RegExp('<br\\s*/?>', 'gi'), '\n');
    text = text.replace(new RegExp('</(p|div|li|h[1-6]|article|section)>', 'gi'), '\n');
    text = text.replace(new RegExp('<[^>]+>', 'g'), ' ');
    text = MetadataService.decodeEntities(text);
    text = text.replace(new RegExp('[ \\t\\r]+', 'g'), ' ');
    text = text.replace(new RegExp('\\n\\s*\\n+', 'g'), '\n\n');
    return text.trim();
  }

  private static metaContent(html: string, key: string): string {
    const tags = html.match(new RegExp('<meta\\s+[^>]*>', 'gi'));
    if (tags === null) {
      return '';
    }
    const keyReg = new RegExp('(?:property|name)\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
    const contentReg = new RegExp('content\\s*=\\s*["\\\']([^"\\\']*)["\\\']', 'i');
    for (let i = 0; i < tags.length; i++) {
      const keyMatch = keyReg.exec(tags[i]);
      if (keyMatch === null) {
        continue;
      }
      if (keyMatch[1].toLowerCase() !== key) {
        continue;
      }
      const contentMatch = contentReg.exec(tags[i]);
      if (contentMatch !== null) {
        return MetadataService.decodeEntities(contentMatch[1]);
      }
    }
    return '';
  }

  private static linkHref(html: string): string {
    const tags = html.match(new RegExp('<link\\s+[^>]*>', 'gi'));
    if (tags === null) {
      return '';
    }
    const relReg = new RegExp('rel\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
    const hrefReg = new RegExp('href\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
    for (let i = 0; i < tags.length; i++) {
      const relMatch = relReg.exec(tags[i]);
      if (relMatch === null || relMatch[1].toLowerCase().indexOf('icon') < 0) {
        continue;
      }
      const hrefMatch = hrefReg.exec(tags[i]);
      if (hrefMatch !== null) {
        return MetadataService.decodeEntities(hrefMatch[1]);
      }
    }
    return '';
  }

  private static resolve(base: string, href: string): string {
    if (href.length === 0) {
      return '';
    }
    try {
      const parsed = new url.URL(href, base);
      const protocol = parsed.protocol.toLowerCase();
      if (protocol !== 'http:' && protocol !== 'https:') {
        return '';
      }
      return parsed.toString();
    } catch (error) {
      return '';
    }
  }

  static async checkLink(targetUrl: string): Promise<number> {
    const request = http.createHttp();
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Phone; HarmonyOS) FlowPage/1.0'
    };
    try {
      const headOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        header: headers,
        connectTimeout: 6000,
        readTimeout: 6000,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      const head = await request.request(targetUrl, headOptions);
      if (head.responseCode >= 200 && head.responseCode < 400) {
        return 1;
      }
      if (head.responseCode === 404 || head.responseCode === 410 || head.responseCode >= 500) {
        return 2;
      }
      if (head.responseCode === 405 || head.responseCode === 403) {
        const getOptions: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: headers,
          connectTimeout: 6000,
          readTimeout: 6000,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false
        };
        const get = await request.request(targetUrl, getOptions);
        if (get.responseCode >= 200 && get.responseCode < 400) {
          return 1;
        }
        if (get.responseCode === 404 || get.responseCode === 410 || get.responseCode >= 500) {
          return 2;
        }
      }
      return 0;
    } catch (error) {
      return 0;
    } finally {
      request.destroy();
    }
  }

  static async fetch(targetUrl: string): Promise<MetadataResult> {
    const result = new MetadataResult();
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': 'Mozilla/5.0 (Phone; HarmonyOS) FlowPage/1.0'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 8000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false
      };
      const response = await request.request(targetUrl, options);
      if (response.responseCode < 200 || response.responseCode >= 400) {
        result.success = false;
        return result;
      }
      let html = '';
      if (response.result instanceof ArrayBuffer) {
        const bytes = new Uint8Array(response.result);
        const limited = bytes.length > Limits.fetchBytes ? bytes.slice(0, Limits.fetchBytes) : bytes;
        html = MetadataService.decodeBytes(limited, response.header);
      }
      if (html.length === 0) {
        result.success = false;
        return result;
      }
      const titleMatch = new RegExp('<title[^>]*>([\\s\\S]*?)</title>', 'i').exec(html);
      const rawTitle = MetadataService.metaContent(html, 'og:title');
      const fallback = titleMatch !== null ? MetadataService.stripTags(titleMatch[1]) : '';
      result.title = rawTitle.length > 0 ? rawTitle : fallback;
      result.description = MetadataService.metaContent(html, 'og:description');
      if (result.description.length === 0) {
        result.description = MetadataService.metaContent(html, 'description');
      }
      result.siteName = MetadataService.metaContent(html, 'og:site_name');
      const image = MetadataService.metaContent(html, 'og:image');
      result.coverUrl = MetadataService.resolve(targetUrl, image);
      const icon = MetadataService.linkHref(html);
      result.faviconUrl = MetadataService.resolve(targetUrl, icon);
      if (result.faviconUrl.length === 0) {
        result.faviconUrl = MetadataService.resolve(targetUrl, '/favicon.ico');
      }
      const bodyText = MetadataService.stripTags(html);
      result.snapshotText = bodyText.length > Limits.snapshotBytes
        ? bodyText.substring(0, Limits.snapshotBytes)
        : bodyText;
      if (result.description.length === 0 && bodyText.length > 0) {
        result.description = bodyText.substring(0, 160);
      }
      result.title = result.title.length > Limits.titleChars
        ? result.title.substring(0, Limits.titleChars)
        : result.title;
      result.description = result.description.length > Limits.descriptionChars
        ? result.description.substring(0, Limits.descriptionChars)
        : result.description;
      result.success = true;
      return result;
    } catch (error) {
      result.success = false;
      return result;
    } finally {
      request.destroy();
    }
  }

  private static decodeBytes(bytes: Uint8Array, header: Object): string {
    let charset = 'utf-8';
    try {
      const headerText = JSON.stringify(header).toLowerCase();
      const match = new RegExp('charset=([a-z0-9_-]+)').exec(headerText);
      if (match !== null) {
        charset = match[1];
      }
    } catch (error) {
      charset = 'utf-8';
    }
    if (charset === 'utf-8') {
      const preview = new util.TextDecoder('utf-8').decodeToString(bytes.slice(0, 2048));
      const metaMatch = new RegExp('<meta[^>]+charset\\s*=\\s*["\\\']?([a-zA-Z0-9_-]+)').exec(preview);
      if (metaMatch !== null) {
        charset = metaMatch[1].toLowerCase();
      }
    }
    try {
      return new util.TextDecoder(charset).decodeToString(bytes);
    } catch (error) {
      try {
        return new util.TextDecoder('utf-8').decodeToString(bytes);
      } catch (inner) {
        return '';
      }
    }
  }
}
