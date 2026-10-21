import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot } from '../core/service/CardSnapshot';

const DOMAIN: number = 0x0000;
const TAG: string = 'flowpage';

export default class TodayCardAbility extends FormExtensionAbility {
  private formIdOf(want: Want): string {
    const params = want.parameters;
    if (params === undefined) {
      return '';
    }
    const identity = params[formInfo.FormParam.IDENTITY_KEY];
    if (typeof identity === 'string') {
      return identity;
    }
    return '';
  }

  private refresh(formId: string): void {
    if (formId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Card refresh called without form id');
      return;
    }
    formProvider.updateForm(formId, CardSnapshot.toBindingData(this.context)).catch((error: BusinessError) => {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to update card formId=%{public}s code=%{public}d reason=%{public}s',
        formId,
        error.code,
        error.message
      );
    });
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.formIdOf(want);
    if (formId.length > 0) {
      CardSnapshot.addFormId(this.context, formId);
    } else {
      hilog.warn(DOMAIN, TAG, 'onAddForm missing form identity');
    }
    return CardSnapshot.toBindingData(this.context);
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {
    CardSnapshot.removeFormId(this.context, formId);
  }
}
