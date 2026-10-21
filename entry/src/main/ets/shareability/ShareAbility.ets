import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { extractFirstUrl } from '../common/UrlUtil';
import { AppState } from '../common/AppState';

const DOMAIN = 0x0000;

export default class ShareAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    AppState.shared.shareContext = this.context;
    systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
      const records = data.getRecords();
      let sharedUrl = '';
      let sharedTitle = '';
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        if (sharedTitle.length === 0 && record.title !== undefined) {
          sharedTitle = record.title;
        }
        if (sharedUrl.length === 0 && record.content !== undefined) {
          sharedUrl = extractFirstUrl(record.content);
        }
        if (sharedUrl.length === 0 && record.uri !== undefined) {
          sharedUrl = extractFirstUrl(record.uri);
        }
      }
      AppStorage.setOrCreate('shared_url', sharedUrl);
      AppStorage.setOrCreate('shared_title', sharedTitle);
      session.loadContent('pages/SharePage');
    }).catch(() => {
      AppStorage.setOrCreate('shared_url', '');
      AppStorage.setOrCreate('shared_title', '');
      session.loadContent('pages/SharePage');
      hilog.error(DOMAIN, 'flowpage', 'Failed to get shared data');
    });
  }
}
