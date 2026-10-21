import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebDavConfig } from './WebDavTransport';
import { CredentialCipher } from '../security/CredentialCipher';

const STORE_NAME: string = 'flowpage_sync';

class StoredConfig {
  url: string = '';
  user: string = '';
  passwordEnc: string = '';
}

export class SyncConfigStore {
  static async load(context: common.Context): Promise<WebDavConfig | undefined> {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = store.getSync('webdav_config', '');
      let urlText = '';
      let userText = '';
      let encryptedText = '';
      if (typeof raw === 'string' && raw.length > 0) {
        const parsed = JSON.parse(raw) as StoredConfig;
        urlText = typeof parsed.url === 'string' ? parsed.url : '';
        userText = typeof parsed.user === 'string' ? parsed.user : '';
        encryptedText = typeof parsed.passwordEnc === 'string' ? parsed.passwordEnc : '';
      }
      if (urlText.length === 0) {
        const url = store.getSync('webdav_url', '');
        const user = store.getSync('webdav_user', '');
        urlText = typeof url === 'string' ? url : '';
        userText = typeof user === 'string' ? user : '';
        const oldEnc = store.getSync('webdav_password_enc', '');
        encryptedText = typeof oldEnc === 'string' ? oldEnc : '';
      }
      if (urlText.length === 0) {
        return undefined;
      }
      let password = '';
      let credentialInvalid = false;
      if (encryptedText.length > 0) {
        try {
          password = await CredentialCipher.decrypt(encryptedText);
          if (password.length === 0) {
            credentialInvalid = true;
          }
        } catch (error) {
          password = '';
          credentialInvalid = true;
          hilog.error(0x0000, 'flowpage', 'credential decrypt failed, password needs re-entry');
        }
      } else {
        credentialInvalid = true;
      }
      const config = new WebDavConfig();
      config.url = urlText;
      config.user = userText;
      config.password = password;
      config.credentialInvalid = credentialInvalid;
      return config;
    } catch (error) {
      return undefined;
    }
  }

  static async save(context: common.Context, config: WebDavConfig): Promise<void> {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    const encrypted = await CredentialCipher.encrypt(config.password);
    const payload = new StoredConfig();
    payload.url = config.url;
    payload.user = config.user;
    payload.passwordEnc = encrypted;
    store.putSync('webdav_config', JSON.stringify(payload));
    store.deleteSync('webdav_url');
    store.deleteSync('webdav_user');
    store.deleteSync('webdav_password_enc');
    store.deleteSync('webdav_password');
    await store.flush();
  }

  static clear(context: common.Context): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.deleteSync('webdav_config');
    store.deleteSync('webdav_url');
    store.deleteSync('webdav_user');
    store.deleteSync('webdav_password');
    store.deleteSync('webdav_password_enc');
    store.deleteSync('last_sync');
    store.flush().catch(() => {});
  }

  static lastSync(context: common.Context): number {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const value = store.getSync('last_sync', 0);
      return typeof value === 'number' ? value : 0;
    } catch (error) {
      return 0;
    }
  }

  static setLastSync(context: common.Context, value: number): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync('last_sync', value);
    store.flush().catch(() => {});
  }
}
