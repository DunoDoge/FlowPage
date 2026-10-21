import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export const CARD_PREFERENCES_NAME: string = 'flowpage_card';
export const CARD_KEY_TODAY_TITLE: string = 'today_title';
export const CARD_KEY_TODAY_DOMAIN: string = 'today_domain';
export const CARD_KEY_TODAY_ID: string = 'today_id';
export const CARD_KEY_TOTAL_COUNT: string = 'total_count';
export const CARD_KEY_RECENT_LINES: string = 'recent_lines';

const FORM_PREFERENCES_NAME: string = 'flowpage_card_forms';
const FORM_IDS_KEY: string = 'form_ids';
const DOMAIN: number = 0x0000;
const TAG: string = 'flowpage';

export class CardValues {
  todayTitle: string = '纸还空着';
  todayDomain: string = '';
  todayId: string = '';
  recentLines: string = '';
  totalCount: string = '0';
}

export class CardSnapshot {
  static readValues(context: common.Context): CardValues {
    const values = new CardValues();
    try {
      const store = CardSnapshot.open(context, CARD_PREFERENCES_NAME);
      const title = store.getSync(CARD_KEY_TODAY_TITLE, '纸还空着');
      const domain = store.getSync(CARD_KEY_TODAY_DOMAIN, '');
      const id = store.getSync(CARD_KEY_TODAY_ID, '');
      const lines = store.getSync(CARD_KEY_RECENT_LINES, '');
      const count = store.getSync(CARD_KEY_TOTAL_COUNT, '0');
      values.todayTitle = typeof title === 'string' ? title : '纸还空着';
      values.todayDomain = typeof domain === 'string' ? domain : '';
      values.todayId = typeof id === 'string' ? id : '';
      values.recentLines = typeof lines === 'string' ? lines : '';
      values.totalCount = typeof count === 'string' ? count : '0';
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to read card snapshot reason=%{public}s', JSON.stringify(error));
    }
    return values;
  }

  static toBindingData(context: common.Context): formBindingData.FormBindingData {
    const values = CardSnapshot.readValues(context);
    const data: Record<string, string> = {
      'today_title': values.todayTitle,
      'today_domain': values.todayDomain,
      'today_id': values.todayId,
      'recent_lines': values.recentLines,
      'total_count': values.totalCount
    };
    return formBindingData.createFormBindingData(data);
  }

  static readFormIds(context: common.Context): string[] {
    const ids: string[] = [];
    try {
      const store = CardSnapshot.open(context, FORM_PREFERENCES_NAME);
      const raw = store.getSync(FORM_IDS_KEY, '');
      if (typeof raw === 'string') {
        CardSnapshot.appendIds(ids, raw);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to read card form ids reason=%{public}s', JSON.stringify(error));
    }
    return ids;
  }

  static setFormIds(context: common.Context, ids: string[]): void {
    try {
      const store = CardSnapshot.open(context, FORM_PREFERENCES_NAME);
      let raw = '';
      for (let i = 0; i < ids.length; i++) {
        if (i > 0) {
          raw += '\n';
        }
        raw += ids[i];
      }
      store.putSync(FORM_IDS_KEY, raw);
      store.flushSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to persist card form ids reason=%{public}s', JSON.stringify(error));
    }
  }

  static addFormId(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids = CardSnapshot.readFormIds(context);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    CardSnapshot.setFormIds(context, ids);
  }

  static removeFormId(context: common.Context, formId: string): void {
    const ids = CardSnapshot.readFormIds(context);
    const next: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        next.push(ids[i]);
      }
    }
    if (next.length === ids.length) {
      return;
    }
    CardSnapshot.setFormIds(context, next);
  }

  private static appendIds(target: string[], raw: string): void {
    const parts = raw.split('\n');
    for (let i = 0; i < parts.length; i++) {
      const id = parts[i].trim();
      if (id.length > 0 && target.indexOf(id) < 0) {
        target.push(id);
      }
    }
  }

  private static open(context: common.Context, name: string): preferences.Preferences {
    // The card extension and the app run in different processes, so drop the
    // cached instance before reading a file that the other process may have written.
    preferences.removePreferencesFromCacheSync(context, name);
    return preferences.getPreferencesSync(context, { name: name });
  }
}
