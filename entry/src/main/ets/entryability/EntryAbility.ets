import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlowRepository } from '../repository/FlowRepository';
import { AppState } from '../common/AppState';
import { shareLinkTargetOf } from '../common/ShareUtil';
import { domainOf } from '../common/UrlUtil';
import { readTextFileAll } from '../common/FileText';
import { Pane } from '../common/Constants';
import { ReadingMode, ReadingSeed } from '../model/ReadingEntry';
import { STRIP_HEIGHT_VP } from '../common/WindowChrome';
import { platformFailure } from '../common/PlatformError';

const DOMAIN = 0x0000;
const ROOT_PAGE: string = 'pages/Index';
const WINDOW_TITLE: string = '流笺';

// Browsers export both extensions; the suffix pair is the fallback signal
// when a want/record carries no utd type.
function hasHtmlSuffix(uri: string): boolean {
  const lower = uri.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

function isBookmarkHtmlUri(uri: string): boolean {
  return uri.startsWith('file://') && hasHtmlSuffix(uri);
}

// Share-panel file delivery: the bookmark HTML record is only readable while
// this want's grant is fresh (official receive pattern), so decode now.
function findSharedBookmarkHtml(records: Array<systemShare.SharedRecord>): string {
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    const uri = record.uri;
    if (uri === undefined || !uri.startsWith('file://')) {
      continue;
    }
    if (record.utd === 'general.html' || hasHtmlSuffix(uri)) {
      return uri;
    }
  }
  return '';
}

export default class EntryAbility extends UIAbility {
  private contentLoaded: boolean = false;
  private continuation: boolean = false;

  private handleWant(want: Want): void {
    // Share-panel delivery of a bookmark HTML file: the panel starts this
    // ability directly (sendData skill); no extension session is involved.
    if (want.action === 'ohos.want.action.sendData') {
      this.handleSharedImport(want);
      return;
    }
    const params = want.parameters;
    if (params !== undefined) {
      const bookmarkId = params['bookmarkId'];
      if (typeof bookmarkId === 'string' && bookmarkId.length > 0) {
        AppState.shared.openBookmark(bookmarkId);
      }
    }
    const uri = want.uri;
    if (uri !== undefined && uri.length > 0) {
      if (isBookmarkHtmlUri(uri)) {
        this.openImportFile(uri);
      } else if (uri.startsWith('flowpage://bookmark/')) {
        AppState.shared.openBookmark(uri.substring('flowpage://bookmark/'.length));
      } else {
        // App Linking share links (https://dunodoge.com/s?u=…) open the
        // wrapped URL straight into the reading layer; other http(s) URIs
        // fall back to the inbox as before.
        const target = shareLinkTargetOf(uri);
        if (target.length > 0) {
          const seed = new ReadingSeed();
          seed.mode = ReadingMode.READER;
          seed.url = target;
          seed.title = domainOf(target);
          seed.transient = true;
          seed.autoLoad = true;
          AppState.shared.openReading(seed);
        } else if (uri.startsWith('http://') || uri.startsWith('https://')) {
          AppState.shared.openInbox(uri);
        }
      }
    }
  }

  // Share-panel handoff: resolve the HTML file record, read the text while
  // the want's URI grant is fresh, stash it, and land on the settings pane
  // for the import preview.
  private handleSharedImport(want: Want): void {
    AppState.shared.goPane(Pane.SETTINGS);
    systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
      const uri = findSharedBookmarkHtml(data.getRecords());
      if (uri.length === 0) {
        hilog.warn(DOMAIN, 'flowpage', 'shared want carried no bookmark html record');
        return;
      }
      return readTextFileAll(uri).then((html: string) => {
        AppState.shared.pendingImportHtml = html;
        hilog.info(DOMAIN, 'flowpage', 'shared bookmark html staged, bytes=%{public}d', html.length);
      });
    }).catch(() => {
      hilog.error(DOMAIN, 'flowpage', 'failed to read shared bookmark html');
      AppState.shared.toast('文件没读懂，请确认是浏览器导出的 HTML');
    });
  }

  // Open-with handoff: read the file while the want's URI grant is fresh,
  // stash the text, and land on the settings pane for the import preview.
  private openImportFile(uri: string): void {
    AppState.shared.goPane(Pane.SETTINGS);
    readTextFileAll(uri).then((html: string) => {
      AppState.shared.pendingImportHtml = html;
    }).catch(() => {
      AppState.shared.toast('文件没读懂，请确认是浏览器导出的 HTML');
    });
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
      hilog.error(DOMAIN, 'flowpage', 'restoreWindowStage failed code=%{public}d', platformFailure(error).code);
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
      this.setupWindowChrome(windowStage);
    });
  }

  // Freeform window chrome recipe: pin the decor strip height, hide the
  // system title bar (freeform state-scoped, no-op elsewhere), disable the
  // default strip drag/double-click (the title strip draws its own), keep
  // the sunk three buttons themed. Every call must run after loadContent
  // takes effect (Stage model constraint), hence the loadRoot callback.
  private setupWindowChrome(windowStage: window.WindowStage): void {
    let mainWindow: window.Window;
    try {
      mainWindow = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.error(DOMAIN, 'flowpage', 'getMainWindowSync failed code=%{public}d', platformFailure(error).code);
      return;
    }
    const appState = AppState.shared;
    const decorStyle: window.DecorButtonStyle = { buttonBackgroundCornerRadius: 6 };
    this.safeDecorCall('decorHeight', (): void => {
      mainWindow.setWindowDecorHeight(STRIP_HEIGHT_VP);
    });
    this.safeDecorCall('decorVisible', (): void => {
      mainWindow.setWindowDecorVisible(false);
    });
    this.safeDecorCall('titleMove', (): void => {
      mainWindow.setWindowTitleMoveEnabled(false);
    });
    this.safeDecorCall('decorStyle', (): void => {
      mainWindow.setDecorButtonStyle(decorStyle);
    });
    // setWindowTitle throws synchronously on abnormal window state (1300002)
    // besides rejecting the promise, so guard both paths.
    try {
      mainWindow.setWindowTitle(WINDOW_TITLE).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, 'flowpage', 'setWindowTitle failed code=%{public}d', error.code);
      });
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'setWindowTitle sync failed code=%{public}d', platformFailure(error).code);
    }
    try {
      appState.freeWindow = mainWindow.isInFreeWindowMode();
      appState.windowStatus = mainWindow.getWindowStatus();
      const rect = mainWindow.getTitleButtonRect();
      appState.titleButtonRight = rect.right;
      appState.titleButtonWidth = rect.width;
      hilog.info(
        DOMAIN,
        'flowpage',
        'windowState init free=%{public}d status=%{public}d rectRight=%{public}d rectWidth=%{public}d',
        appState.freeWindow ? 1 : 0,
        appState.windowStatus,
        appState.titleButtonRight,
        appState.titleButtonWidth
      );
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'window state sync failed code=%{public}d', platformFailure(error).code);
    }
    try {
      mainWindow.on('freeWindowModeChange', (free: boolean) => {
        appState.freeWindow = free;
        hilog.info(DOMAIN, 'flowpage', 'windowState freeWindowModeChange free=%{public}d', free ? 1 : 0);
      });
      mainWindow.on('windowStatusChange', (status: window.WindowStatusType) => {
        appState.windowStatus = status;
        hilog.info(DOMAIN, 'flowpage', 'windowState windowStatusChange status=%{public}d', status);
      });
      mainWindow.on('windowTitleButtonRectChange', (rect: window.TitleButtonRect) => {
        appState.titleButtonRight = rect.right;
        appState.titleButtonWidth = rect.width;
        hilog.info(
          DOMAIN,
          'flowpage',
          'windowState titleButtonRectChange right=%{public}d width=%{public}d',
          rect.right,
          rect.width
        );
      });
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'window listeners failed code=%{public}d', platformFailure(error).code);
    }
  }

  private safeDecorCall(label: string, call: () => void): void {
    try {
      call();
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'decor %{public}s failed code=%{public}d', label, platformFailure(error).code);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppState.shared.abilityContext = this.context;
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
