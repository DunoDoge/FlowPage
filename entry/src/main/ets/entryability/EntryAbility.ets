import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlowRepository } from '../repository/FlowRepository';
import { AppState } from '../common/AppState';

const DOMAIN = 0x0000;
const ROOT_PAGE: string = 'pages/Index';

export default class EntryAbility extends UIAbility {
  private contentLoaded: boolean = false;
  private continuation: boolean = false;

  private handleWant(want: Want): void {
    const params = want.parameters;
    if (params !== undefined) {
      const bookmarkId = params['bookmarkId'];
      if (typeof bookmarkId === 'string' && bookmarkId.length > 0) {
        AppState.shared.openBookmark(bookmarkId);
      }
    }
    const uri = want.uri;
    if (uri !== undefined && uri.length > 0) {
      if (uri.startsWith('flowpage://bookmark/')) {
        AppState.shared.openBookmark(uri.substring('flowpage://bookmark/'.length));
      } else if (uri.startsWith('http://') || uri.startsWith('https://')) {
        AppState.shared.openInbox(uri);
      }
    }
  }

  private prepareContinuation(launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    this.continuation = true;
    this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'flowpage', 'setMissionContinueState failed code=%{public}d', error.code);
    });
    try {
      this.context.restoreWindowStage(new LocalStorage());
      hilog.info(DOMAIN, 'flowpage', '%{public}s', 'continuation restoreWindowStage called');
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.error(DOMAIN, 'flowpage', 'restoreWindowStage failed code=%{public}d', businessError.code);
    }
  }

  private loadRoot(windowStage: window.WindowStage): void {
    if (this.contentLoaded) {
      return;
    }
    this.contentLoaded = true;
    windowStage.loadContent(ROOT_PAGE, (err) => {
      if (err.code) {
        this.contentLoaded = false;
        hilog.error(DOMAIN, 'flowpage', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Succeeded in loading the content.');
    });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'flowpage', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(
      DOMAIN,
      'flowpage',
      'Ability onCreate launchReason=%{public}d message=%{public}s',
      launchParam.launchReason,
      launchParam.launchReasonMessage
    );
    this.handleWant(want);
    this.prepareContinuation(launchParam);
    FlowRepository.get().init(this.context).catch(() => {
      AppState.shared.toast('本地数据没有打开');
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(
      DOMAIN,
      'flowpage',
      'Ability onNewWant launchReason=%{public}d message=%{public}s',
      launchParam.launchReason,
      launchParam.launchReasonMessage
    );
    this.handleWant(want);
    this.prepareContinuation(launchParam);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
    const id = AppState.shared.selectedId;
    if (id.length > 0) {
      wantParam['bookmarkId'] = id;
    }
    hilog.info(DOMAIN, 'flowpage', 'Ability onContinue hasBookmark=%{public}s', id.length > 0 ? 'true' : 'false');
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Ability onWindowStageCreate');
    this.loadRoot(windowStage);
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'flowpage', 'Ability onWindowStageRestore continuation=%{public}s', this.continuation ? 'true' : 'false');
    this.loadRoot(windowStage);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'flowpage', '%{public}s', 'Ability onBackground');
  }
}
