import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { platformFailure } from '../../common/PlatformError';
import { RemoteItem, WebDavResponse } from './WebDavTypes';
import { SyncTransport } from './SyncTransport';
import { WebDavPacer, WebDavRetryPlanner } from './WebDavRetryPlanner';
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
  // Run-scoped throttle state: pacer spaces requests after an exhausted
  // 429/503; hardThrottled makes every further request fail fast so the
  // engine can end the round (remaining work resumes next sync).
  private pacer: WebDavPacer = new WebDavPacer();
  private hardThrottled: boolean = false;

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

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  // Transient failures (429/502/503/504, network errors) retry with backoff
  // before surfacing; every other status returns to the caller unchanged so
  // LWW/If-Match and auth handling keep their fail-fast semantics.
  private async request(
    method: string,
    path: string,
    body: string,
    extra: Record<string, string>
  ): Promise<WebDavResponse> {
    if (this.hardThrottled) {
      throw new Error('THROTTLED_ABORT');
    }
    const url = `${this.base()}/${path}`;
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
    let attempts = 0;
    while (true) {
      if (this.pacer.pacing()) {
        await WebDavTransport.sleep(this.pacer.currentDelayMs());
      }
      attempts = attempts + 1;
      const request = http.createHttp();
      try {
        hilog.info(0x0000, 'flowpage', 'webdav request %{public}s %{public}s', method, this.safeUrl(url));
        const response = await request.request(url, options);
        hilog.info(0x0000, 'flowpage', 'webdav response %{public}d %{public}s', response.responseCode, method);
        const result = new WebDavResponse();
        result.status = response.responseCode;
        const payload = response.result;
        result.body = typeof payload === 'string' ? payload : '';
        const responseHeaders = response.header as Record<string, string>;
        result.etag = this.headerValue(responseHeaders, 'etag');
        if (WebDavRetryPlanner.isRetryableStatus(result.status)) {
          const retryAfterMs = WebDavRetryPlanner.retryAfterMillis(
            Number(this.headerValue(responseHeaders, 'retry-after'))
          );
          const decision = WebDavRetryPlanner.planForStatus(attempts, result.status, retryAfterMs);
          if (decision.retry) {
            hilog.info(
              0x0000,
              'flowpage',
              'webdav retry %{public}s status=%{public}d attempt=%{public}d delay=%{public}dms',
              method,
              result.status,
              attempts,
              decision.delayMs
            );
            await WebDavTransport.sleep(decision.delayMs);
            continue;
          }
          hilog.warn(
            0x0000,
            'flowpage',
            'webdav retries exhausted %{public}s status=%{public}d attempt=%{public}d',
            method,
            result.status,
            attempts
          );
          if (this.pacer.recordThrottled(result.status, retryAfterMs)) {
            this.hardThrottled = true;
            hilog.warn(0x0000, 'flowpage', 'webdav throttle circuit open, aborting sync round');
            throw new Error('THROTTLED_ABORT');
          }
          hilog.info(0x0000, 'flowpage', 'webdav pacing on, delay=%{public}dms', this.pacer.currentDelayMs());
          return result;
        }
        if (result.status < 400) {
          this.pacer.recordSuccess();
        }
        return result;
      } catch (error) {
        if (error instanceof Error && error.message === 'THROTTLED_ABORT') {
          throw error;
        }
        const code = platformFailure(error).code;
        const decision = WebDavRetryPlanner.planForNetworkError(attempts);
        if (decision.retry) {
          hilog.info(
            0x0000,
            'flowpage',
            'webdav retry %{public}s net code=%{public}d attempt=%{public}d delay=%{public}dms',
            method,
            code,
            attempts,
            decision.delayMs
          );
          await WebDavTransport.sleep(decision.delayMs);
          continue;
        }
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
