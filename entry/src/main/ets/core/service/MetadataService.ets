import { http } from '@kit.NetworkKit';
import { util, url } from '@kit.ArkTS';
import { Limits } from '../../common/Constants';
import { resolveHttpUrl } from '../../common/UrlUtil';
import { MetadataResult } from '../../model/MetadataResult';
import { ArticleExtractor } from '../parser/ArticleExtractor';
import { ArticleExtractService } from './ArticleExtractService';

const ENTITY_VALUES: string[] = ['&', '<', '>', '"', '\'', '\'', ' '];
const ENTITY_REGEXES: RegExp[] = [
  new RegExp('&amp;', 'g'),
  new RegExp('&lt;', 'g'),
  new RegExp('&gt;', 'g'),
  new RegExp('&quot;', 'g'),
  new RegExp('&#39;', 'g'),
  new RegExp('&apos;', 'g'),
  new RegExp('&nbsp;', 'g')
];
const RE_SCRIPT = new RegExp('<script[\\s\\S]*?</script>', 'gi');
const RE_STYLE = new RegExp('<style[\\s\\S]*?</style>', 'gi');
const RE_COMMENT = new RegExp('<!--[\\s\\S]*?-->', 'g');
const RE_BR = new RegExp('<br\\s*/?>', 'gi');
const RE_BLOCK_END = new RegExp('</(p|div|li|h[1-6]|article|section)>', 'gi');
const RE_TAG = new RegExp('<[^>]+>', 'g');
const RE_INLINE_WS = new RegExp('[ \\t\\r]+', 'g');
const RE_BLANK_LINES = new RegExp('\\n\\s*\\n+', 'g');
const RE_META_TAG = new RegExp('<meta\\s+[^>]*>', 'gi');
const RE_ATTR_KEY = new RegExp('(?:property|name)\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
const RE_ATTR_CONTENT = new RegExp('content\\s*=\\s*["\\\']([^"\\\']*)["\\\']', 'i');
const RE_LINK_TAG = new RegExp('<link\\s+[^>]*>', 'gi');
const RE_REL = new RegExp('rel\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
const RE_HREF = new RegExp('href\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
const RE_BASE_TAG = new RegExp('<base\\s+[^>]*>', 'gi');
const RE_TITLE = new RegExp('<title[^>]*>([\\s\\S]*?)</title>', 'i');
const RE_CHARSET_HEADER = new RegExp('charset=([a-z0-9_-]+)');
const RE_CHARSET_META = new RegExp('<meta[^>]+charset\\s*=\\s*["\\\']?([a-zA-Z0-9_-]+)');

export class MetadataService {
  private static decodeEntities(input: string): string {
    let text = input;
    for (let i = 0; i < ENTITY_REGEXES.length; i++) {
      text = text.replace(ENTITY_REGEXES[i], ENTITY_VALUES[i]);
    }
    return text;
  }

  static stripTags(html: string): string {
    let text = html;
    text = text.replace(RE_SCRIPT, ' ');
    text = text.replace(RE_STYLE, ' ');
    text = text.replace(RE_COMMENT, ' ');
    text = text.replace(RE_BR, '\n');
    text = text.replace(RE_BLOCK_END, '\n');
    text = text.replace(RE_TAG, ' ');
    text = MetadataService.decodeEntities(text);
    text = text.replace(RE_INLINE_WS, ' ');
    text = text.replace(RE_BLANK_LINES, '\n\n');
    return text.trim();
  }

  private static metaContent(html: string, key: string): string {
    const tags = html.match(RE_META_TAG);
    if (tags === null) {
      return '';
    }

    for (let i = 0; i < tags.length; i++) {
      const keyMatch = RE_ATTR_KEY.exec(tags[i]);
      if (keyMatch === null) {
        continue;
      }
      if (keyMatch[1].toLowerCase() !== key) {
        continue;
      }
      const contentMatch = RE_ATTR_CONTENT.exec(tags[i]);
      if (contentMatch !== null) {
        return MetadataService.decodeEntities(contentMatch[1]);
      }
    }
    return '';
  }

  private static linkHref(html: string): string {
    const tags = html.match(RE_LINK_TAG);
    if (tags === null) {
      return '';
    }

    for (let i = 0; i < tags.length; i++) {
      const relMatch = RE_REL.exec(tags[i]);
      if (relMatch === null || relMatch[1].toLowerCase().indexOf('icon') < 0) {
        continue;
      }
      const hrefMatch = RE_HREF.exec(tags[i]);
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

  private static documentBase(pageUrl: string, html: string): string {
    const tags = html.match(RE_BASE_TAG);
    if (tags === null) {
      return pageUrl;
    }
    for (let i = 0; i < tags.length; i++) {
      const hrefMatch = RE_HREF.exec(tags[i]);
      if (hrefMatch === null) {
        continue;
      }
      const resolved = resolveHttpUrl(pageUrl, MetadataService.decodeEntities(hrefMatch[1]));
      if (resolved.length > 0) {
        return resolved;
      }
    }
    return pageUrl;
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

  static async fetch(targetUrl: string, includeSnapshot: boolean = true, offThread: boolean = false): Promise<MetadataResult> {
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
      const titleMatch = RE_TITLE.exec(html);
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
      let bodyText = '';
      if (includeSnapshot) {
        const base = MetadataService.documentBase(targetUrl, html);
        const article = offThread
          ? await ArticleExtractService.extractAsync(html, result.title, base)
          : ArticleExtractor.extract(html, result.title, base);
        article.truncate(Limits.snapshotBytes);
        result.article = article;
        bodyText = article.plainText();
      } else {
        bodyText = MetadataService.stripTags(html);
      }
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
      const match = RE_CHARSET_HEADER.exec(headerText);
      if (match !== null) {
        charset = match[1];
      }
    } catch (error) {
      charset = 'utf-8';
    }
    if (charset === 'utf-8') {
      const preview = new util.TextDecoder('utf-8').decodeToString(bytes.slice(0, 2048));
      const metaMatch = RE_CHARSET_META.exec(preview);
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
