import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { platformFailure } from '../../common/PlatformError';
import { RemoteItem, WebDavResponse } from './WebDavTypes';
import { SyncTransport } from './SyncTransport';
import { WebDavXml } from './WebDavXml';

const PROPFIND_BODY: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getetag/></D:prop></D:propfind>';

export class WebDavConfig {
  url: string = '';
  user: string = '';
  password: string = '';
  credentialInvalid: boolean = false;
}

export class WebDavTransport implements SyncTransport {
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

  private headerValue(headers: Record<string, string>, name: string): string {
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === name) {
        return headers[keys[i]];
      }
    }
    return '';
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
      result.etag = this.headerValue(responseHeaders, 'etag');
      return result;
    } catch (error) {
      const code = platformFailure(error).code;
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
    await this.ensureCollection('FlowPage/v1/folders');
    await this.ensureCollection('FlowPage/v1/tombstones');
  }

  private async listCollection(dir: string, emptyOn404: boolean): Promise<RemoteItem[]> {
    const response = await this.request('PROPFIND', `FlowPage/v1/${dir}/`, PROPFIND_BODY, {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8'
    });
    if (response.status === 404 && emptyOn404) {
      return [];
    }
    if (response.status === 404) {
      throw new Error('NOT_FOUND');
    }
    if (response.status === 401) {
      throw new Error('AUTH_401');
    }
    if (response.status === 403) {
      throw new Error('AUTH_403');
    }
    if (response.status !== 207 && response.status !== 200) {
      throw new Error(`PROPFIND_${response.status}`);
    }
    return WebDavXml.parseItems(response.body);
  }

  async listItems(): Promise<RemoteItem[]> {
    return this.listCollection('items', false);
  }

  async listFolders(): Promise<RemoteItem[]> {
    return this.listCollection('folders', true);
  }

  async listTombstones(): Promise<string[]> {
    const response = await this.request('PROPFIND', 'FlowPage/v1/tombstones/', PROPFIND_BODY, {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8'
    });
    if (response.status === 404) {
      return [];
    }
    if (response.status === 401) {
      throw new Error('AUTH_401');
    }
    if (response.status === 403) {
      throw new Error('AUTH_403');
    }
    if (response.status !== 207 && response.status !== 200) {
      throw new Error(`PROPFIND_${response.status}`);
    }
    const items = WebDavXml.parseItems(response.body);
    const ids: string[] = [];
    for (let i = 0; i < items.length; i++) {
      ids.push(items[i].name);
    }
    return ids;
  }

  async putTombstone(id: string): Promise<void> {
    const body = `{"schema":1,"id":${JSON.stringify(id)},"purgedAt":${Date.now()}}`;
    const response = await this.request(
      'PUT',
      `FlowPage/v1/tombstones/${encodeURIComponent(id)}.json`,
      body,
      {
        'Content-Type': 'application/json; charset=utf-8'
      }
    );
    if (response.status !== 201 && response.status !== 200 && response.status !== 204) {
      throw new Error(`PUT_${response.status}`);
    }
  }

  private async collectionGet(dir: string, name: string): Promise<WebDavResponse> {
    return this.request('GET', `FlowPage/v1/${dir}/${encodeURIComponent(name)}.json`, '', {});
  }

  async get(name: string): Promise<WebDavResponse> {
    return this.collectionGet('items', name);
  }

  async getFolder(name: string): Promise<WebDavResponse> {
    return this.collectionGet('folders', name);
  }

  private async stat(dir: string, name: string): Promise<string> {
    const response = await this.request(
      'PROPFIND',
      `FlowPage/v1/${dir}/${encodeURIComponent(name)}.json`,
      PROPFIND_BODY,
      {
        'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8'
      }
    );
    if (response.status !== 207 && response.status !== 200) {
      return '';
    }
    return WebDavXml.parseEtag(response.body);
  }

  private async collectionPut(dir: string, name: string, json: string, etag: string): Promise<string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8'
    };
    if (etag.length > 0) {
      headers['If-Match'] = etag;
    }
    const response = await this.request(
      'PUT',
      `FlowPage/v1/${dir}/${encodeURIComponent(name)}.json`,
      json,
      headers
    );
    if (response.status !== 201 && response.status !== 200 && response.status !== 204) {
      const detail = response.body.length > 0 ? response.body.substring(0, 240) : '';
      hilog.error(
        0x0000,
        'flowpage',
        'webdav PUT failed status=%{public}d body=%{public}s',
        response.status,
        detail
      );
      throw new Error(`PUT_${response.status}`);
    }
    let syncedEtag = response.etag;
    if (syncedEtag.length === 0) {
      try {
        syncedEtag = await this.stat(dir, name);
      } catch (error) {
        syncedEtag = '';
      }
      hilog.info(
        0x0000,
        'flowpage',
        'webdav PUT etag fallback %{public}s',
        syncedEtag.length > 0 ? 'ok' : 'missing'
      );
    }
    return syncedEtag;
  }

  async put(name: string, json: string, etag: string): Promise<string> {
    return this.collectionPut('items', name, json, etag);
  }

  async putFolder(name: string, json: string, etag: string): Promise<string> {
    return this.collectionPut('folders', name, json, etag);
  }

  private async collectionRemove(dir: string, name: string): Promise<void> {
    const response = await this.request(
      'DELETE',
      `FlowPage/v1/${dir}/${encodeURIComponent(name)}.json`,
      '',
      {}
    );
    if (response.status !== 204 && response.status !== 200 && response.status !== 404) {
      throw new Error(`DELETE_${response.status}`);
    }
  }

  async remove(name: string): Promise<void> {
    await this.collectionRemove('items', name);
  }

  async removeFolder(name: string): Promise<void> {
    await this.collectionRemove('folders', name);
  }
}
