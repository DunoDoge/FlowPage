import { common } from '@kit.AbilityKit';
import { formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot } from './CardSnapshot';

const DOMAIN: number = 0x0000;
const TAG: string = 'flowpage';

export class CardPublisher {
  static async publish(context: common.Context): Promise<void> {
    const formIds = await CardPublisher.resolveFormIds(context);
    if (formIds.length === 0) {
      return;
    }
    const data = CardSnapshot.toBindingData(context);
    for (let i = 0; i < formIds.length; i++) {
      const formId = formIds[i];
      try {
        await formProvider.updateForm(formId, data);
      } catch (error) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Failed to update card formId=%{public}s reason=%{public}s',
          formId,
          JSON.stringify(error)
        );
      }
    }
  }

  private static async resolveFormIds(context: common.Context): Promise<string[]> {
    const ids: string[] = [];
    try {
      const infos: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      for (let i = 0; i < infos.length; i++) {
        const formId = infos[i].formId;
        if (formId.length > 0 && ids.indexOf(formId) < 0) {
          ids.push(formId);
        }
      }
      if (ids.length > 0) {
        // Refresh the persisted list so cards added before this build are covered
        // and stale ids left by the card preview flow are dropped.
        CardSnapshot.setFormIds(context, ids);
        return ids;
      }
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Card discovery failed, falling back to persisted ids reason=%{public}s',
        JSON.stringify(error)
      );
    }
    return CardSnapshot.readFormIds(context);
  }
}
