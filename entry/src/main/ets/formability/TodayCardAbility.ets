import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

class CardValues {
  todayTitle: string = '纸还空着';
  todayDomain: string = '';
  todayId: string = '';
  recentLines: string = '';
  totalCount: string = '0';
}

export default class TodayCardAbility extends FormExtensionAbility {
  private readValues(): CardValues {
    const values = new CardValues();
    try {
      const store = preferences.getPreferencesSync(this.context, { name: 'flowpage_card' });
      const title = store.getSync('today_title', '纸还空着');
      const domain = store.getSync('today_domain', '');
      const id = store.getSync('today_id', '');
      const lines = store.getSync('recent_lines', '');
      const count = store.getSync('total_count', '0');
      values.todayTitle = typeof title === 'string' ? title : '纸还空着';
      values.todayDomain = typeof domain === 'string' ? domain : '';
      values.todayId = typeof id === 'string' ? id : '';
      values.recentLines = typeof lines === 'string' ? lines : '';
      values.totalCount = typeof count === 'string' ? count : '0';
    } catch (error) {
      hilog.error(0x0000, 'flowpage', 'Failed to read card snapshot');
    }
    return values;
  }

  private toBindingData(): formBindingData.FormBindingData {
    const values = this.readValues();
    const data: Record<string, string> = {
      'today_title': values.todayTitle,
      'today_domain': values.todayDomain,
      'today_id': values.todayId,
      'recent_lines': values.recentLines,
      'total_count': values.totalCount
    };
    return formBindingData.createFormBindingData(data);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    return this.toBindingData();
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, this.toBindingData()).catch(() => {});
  }

  onFormEvent(formId: string, message: string): void {
    formProvider.updateForm(formId, this.toBindingData()).catch(() => {});
  }
}
