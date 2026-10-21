import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const KEY_ALIAS: string = 'flowpage_sync_credential_key';
const AAD_TEXT: string = 'flowpage-sync-credential';

function stringToBytes(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function bytesToString(value: Uint8Array): string {
  return new util.TextDecoder('utf-8').decodeToString(value);
}

function base64(value: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(value);
}

function fromBase64(value: string): Uint8Array {
  return new util.Base64Helper().decodeSync(value);
}

function generateProperties(): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }
  ];
  return properties;
}

function encryptProperties(nonce: Uint8Array): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
    { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: stringToBytes(AAD_TEXT) }
  ];
  return properties;
}

function decryptProperties(nonce: Uint8Array, tag: Uint8Array): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
    { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: stringToBytes(AAD_TEXT) },
    { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag }
  ];
  return properties;
}

export class CredentialCipher {
  private static async ensureKey(): Promise<void> {
    let exists = false;
    try {
      exists = await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
    } catch (error) {
      exists = false;
    }
    if (exists) {
      return;
    }
    const options: huks.HuksOptions = { properties: generateProperties() };
    await huks.generateKeyItem(KEY_ALIAS, options);
  }

  static async encrypt(plainText: string): Promise<string> {
    await CredentialCipher.ensureKey();
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const options: huks.HuksOptions = {
      properties: encryptProperties(nonce),
      inData: stringToBytes(plainText)
    };
    const session = await huks.initSession(KEY_ALIAS, options);
    const result = await huks.finishSession(session.handle, options);
    const cipher = result.outData !== undefined ? result.outData : new Uint8Array(0);
    return `${base64(nonce)}:${base64(cipher)}`;
  }

  static async decrypt(stored: string): Promise<string> {
    try {
      return await CredentialCipher.decryptInner(stored);
    } catch (error) {
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? -1 : businessError.code;
      hilog.error(0x0000, 'flowpage', 'credential decrypt failed code=%{public}d message=%{public}s', code, businessError.message);
      throw new Error(`HUKS_${code}`);
    }
  }

  private static async decryptInner(stored: string): Promise<string> {
    const parts = stored.split(':');
    if (parts.length !== 2) {
      throw new Error('BAD_FORMAT');
    }
    const nonce = fromBase64(parts[0]);
    const cipher = fromBase64(parts[1]);
    if (cipher.length <= 16) {
      throw new Error('BAD_CIPHER');
    }
    const data = cipher.slice(0, cipher.length - 16);
    const tag = cipher.slice(cipher.length - 16);
    const options: huks.HuksOptions = {
      properties: decryptProperties(nonce, tag),
      inData: data
    };
    const session = await huks.initSession(KEY_ALIAS, options);
    const result = await huks.finishSession(session.handle, options);
    if (result.outData === undefined) {
      throw new Error('EMPTY_RESULT');
    }
    return bytesToString(result.outData);
  }
}
