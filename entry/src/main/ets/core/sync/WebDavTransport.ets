import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const PROPFIND_BODY: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getetag/></D:prop></D:propfind>';

export class WebDavConfig {
  url: string = '';
  user: string = '';
  password: string = '';
  credentialInvalid: boolean = false;
}

export class RemoteItem {
  name: string = '';
  etag: string = '';
}

export class WebDavResponse {
  status: number = 0;
  body: string = '';
  etag: string = '';
}

export class WebDavTransport {
  private config: WebDavConfig;
  private auth: string;

  constructor(config: WebDavConfig) {
    this.config = config;
    const bytes = new util.TextEncoder().encodeInto(`${config.user}:${config.password}`);
    this.auth = `Basic ${new util.Base64Helper().encodeToStringSync(bytes)}`;
  }

  private base(): string {
    let value = this.config.url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  private safeUrl(url: string): string {
    const schemeEnd = url.indexOf('://');
    const at = url.indexOf('@');
    if (schemeEnd >= 0 && at > schemeEnd + 3) {
      return `${url.substring(0, schemeEnd + 3)}***@${url.substring(at + 1)}`;
    }
    return url;
  }

  private async request(
    method: string,
    path: string,
    body: string,
    extra: Record<string, string>
  ): Promise<WebDavResponse> {
    const request = http.createHttp();
    const url = `${this.base()}/${path}`;
    try {
      const headers: Record<string, string> = {
        'Authorization': this.auth,
        'Accept': '*/*'
      };
      const extraKeys = Object.keys(extra);
      for (let i = 0; i < extraKeys.length; i++) {
        headers[extraKeys[i]] = extra[extraKeys[i]];
      }
      const methodValue: http.RequestMethod = method as http.RequestMethod;
      const options: http.HttpRequestOptions = {
        method: methodValue,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      if (body.length > 0) {
        options.extraData = body;
      }
      hilog.info(0x0000, 'flowpage', 'webdav request %{public}s %{public}s', method, this.safeUrl(url));
      const response = await request.request(url, options);
      hilog.info(0x0000, 'flowpage', 'webdav response %{public}d %{public}s', response.responseCode, method);
      const result = new WebDavResponse();
      result.status = response.responseCode;
      const payload = response.result;
      result.body = typeof payload === 'string' ? payload : '';
      const responseHeaders = response.header as Record<string, string>;
      const etag = responseHeaders['etag'];
      const etagUpper = responseHeaders['ETag'];
      result.etag = etag !== undefined ? etag : (etagUpper !== undefined ? etagUpper : '');
      return result;
    } catch (error) {
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? 0 : businessError.code;
      hilog.error(
        0x0000,
        'flowpage',
        'webdav error %{public}s %{public}s code=%{public}d',
        method,
        this.safeUrl(url),
        code
      );
      throw new Error(`NET_${code}`);
    } finally {
      request.destroy();
    }
  }

  async test(): Promise<number> {
    const response = await this.request('PROPFIND', '', PROPFIND_BODY, {
      'Depth': '0',
      'Content-Type': 'application/xml; charset=utf-8'
    });
    if (response.status === 401) {
      throw new Error('AUTH_401');
    }
    if (response.status === 403) {
      throw new Error('AUTH_403');
    }
    if (response.status === 404) {
      throw new Error('NOT_FOUND');
    }
    if (response.status !== 207 && response.status !== 200) {
      throw new Error(`STATUS_${response.status}`);
    }
    return response.status;
  }

  async ensureCollection(path: string): Promise<void> {
    const response = await this.request('MKCOL', path, '', {});
    if (response.status === 201 || response.status === 200 || response.status === 405) {
      return;
    }
    if (response.status === 401) {
      throw new Error('AUTH_401');
    }
    if (response.status === 403) {
      throw new Error('AUTH_403');
    }
    if (response.status === 409) {
      throw new Error('PARENT_MISSING');
    }
    throw new Error(`MKCOL_${response.status}`);
  }

  async ensureBase(): Promise<void> {
    await this.ensureCollection('FlowPage');
    await this.ensureCollection('FlowPage/v1');
    await this.ensureCollection('FlowPage/v1/items');
  }

  private decodeHref(value: string): string {
    let text = value;
    text = text.replace(new RegExp('&amp;', 'g'), '&');
    text = text.replace(new RegExp('&lt;', 'g'), '<');
    text = text.replace(new RegExp('&gt;', 'g'), '>');
    text = text.replace(new RegExp('&quot;', 'g'), '"');
    return text;
  }

  async listItems(): Promise<RemoteItem[]> {
    const response = await this.request('PROPFIND', 'FlowPage/v1/items/', PROPFIND_BODY, {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8'
    });
    if (response.status === 401) {
      throw new Error('AUTH_401');
    }
    if (response.status === 403) {
      throw new Error('AUTH_403');
    }
    if (response.status === 404) {
      throw new Error('NOT_FOUND');
    }
    if (response.status !== 207 && response.status !== 200) {
      throw new Error(`PROPFIND_${response.status}`);
    }
    const items: RemoteItem[] = [];
    const blocks = response.body.match(new RegExp('<[^>]*response[^>]*>[\\s\\S]*?</[^>]*response>', 'gi'));
    if (blocks === null) {
      return items;
    }
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      const hrefMatch = new RegExp('<[^>]*href[^>]*>([^<]*)<', 'i').exec(block);
      if (hrefMatch === null) {
        continue;
      }
      let href = this.decodeHref(hrefMatch[1].trim());
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
      const etagMatch = new RegExp('<[^>]*getetag[^>]*>([^<]*)<', 'i').exec(block);
      const item = new RemoteItem();
      item.name = name.substring(0, name.length - 5);
      item.etag = etagMatch !== null ? this.decodeHref(etagMatch[1].trim()) : '';
      items.push(item);
    }
    return items;
  }

  async get(name: string): Promise<WebDavResponse> {
    return this.request('GET', `FlowPage/v1/items/${encodeURIComponent(name)}.json`, '', {});
  }

  async put(name: string, json: string, etag: string): Promise<string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8'
    };
    if (etag.length > 0) {
      headers['If-Match'] = etag;
    } else {
      headers['If-None-Match'] = '*';
    }
    const response = await this.request(
      'PUT',
      `FlowPage/v1/items/${encodeURIComponent(name)}.json`,
      json,
      headers
    );
    if (response.status !== 201 && response.status !== 200 && response.status !== 204) {
      throw new Error(`PUT_${response.status}`);
    }
    return response.etag;
  }

  async remove(name: string): Promise<void> {
    const response = await this.request('DELETE', `FlowPage/v1/items/${encodeURIComponent(name)}.json`, '', {});
    if (response.status !== 204 && response.status !== 200 && response.status !== 404) {
      throw new Error(`DELETE_${response.status}`);
    }
  }
}
