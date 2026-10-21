import { RemoteItem, WebDavResponse } from './WebDavTypes';

export interface SyncTransport {
  test(): Promise<number>;
  ensureBase(): Promise<void>;
  listItems(): Promise<RemoteItem[]>;
  get(name: string): Promise<WebDavResponse>;
  put(name: string, json: string, etag: string): Promise<string>;
  remove(name: string): Promise<void>;
}
