import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppState } from './AppState';
import { platformFailure } from './PlatformError';

const TAG: string = 'flowpage';
const LAUNCH_FAILED_TOAST: string = '分享面板拉起失败，请重试';

export class ShareLink {
  url: string = '';
  title: string = '';
  description: string = '';
}

// Pure record construction kept free of panel state so device tests can verify
// the data shape without a live ShareController. Empty titles fall back to the
// URL (spec); records carry URL/title/description only. (App Linking wrapping
// stays dormant until the dunodoge.com /s endpoint goes live -- see design D7.)
export function buildShareRecords(links: ShareLink[]): systemShare.SharedRecord[] {
  const records: systemShare.SharedRecord[] = [];
  for (let i = 0; i < links.length; i++) {
    const link = links[i];
    const title = link.title.trim();
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
      content: link.url,
      title: title.length > 0 ? title : link.url,
      description: link.description
    };
    records.push(record);
  }
  return records;
}

// The platform has no multi-record text channel (Share Kit FAQ: multi
// plain-text records are unsupported; receivers flatten them -- QQ joins all
// records into one line, Notes keeps only the first -- and Huawei Share
// refuses non-file batches). Multi-share therefore aggregates into ONE
// plain-text record, URLs space-joined on a SINGLE line: QQ parses a shared
// text record as one link schema, so both leading title words and embedded
// newlines make it fail with "schema不合法" (real-device findings); the
// single-line join mirrors what QQ itself produces when it concatenates
// records.
export function buildAggregatedRecord(links: ShareLink[]): systemShare.SharedRecord {
  const parts: string[] = [];
  for (let i = 0; i < links.length; i++) {
    parts.push(links[i].url);
  }
  const record: systemShare.SharedRecord = {
    utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
    content: parts.join(' '),
    title: `${links.length} 条链接`,
    description: ''
  };
  return record;
}

export class ShareOut {
  private static controller: systemShare.ShareController | undefined = undefined;
  private static onPanelDismissed: () => void = () => {};

  // Returns undefined (after toasting) when record construction throws.
  private static buildController(links: ShareLink[]): systemShare.ShareController | undefined {
    try {
      // Always exactly one outbound record: HYPERLINK for a single bookmark,
      // aggregated PLAIN_TEXT for multi (see buildAggregatedRecord).
      const record = links.length === 1 ? buildShareRecords(links)[0] : buildAggregatedRecord(links);
      const data = new systemShare.SharedData(record);
      return new systemShare.ShareController(data);
    } catch (error) {
      const failure = platformFailure(error);
      hilog.warn(0x0000, TAG, `share data build failed: ${failure.code} ${failure.message}`);
      AppState.shared.toast(LAUNCH_FAILED_TOAST);
      return undefined;
    }
  }

  static shareBookmarks(links: ShareLink[]): void {
    if (links.length === 0) {
      return;
    }
    const context = AppState.shared.abilityContext;
    if (context === undefined) {
      AppState.shared.toast(LAUNCH_FAILED_TOAST);
      return;
    }
    ShareOut.dismiss();
    const controller = ShareOut.buildController(links);
    if (controller === undefined) {
      return;
    }
    ShareOut.onPanelDismissed = () => {
      if (ShareOut.controller === controller) {
        ShareOut.controller = undefined;
      }
    };
    try {
      controller.on('dismiss', ShareOut.onPanelDismissed);
    } catch (error) {
      // Listener registration must not block the launch itself.
    }
    ShareOut.controller = controller;
    // One outbound record in both shapes, so SINGLE mode covers everything;
    // BATCH is reserved for multi-file records on this platform. Preview:
    // a single hyperlink rides DETAIL for its title + summary card, while
    // the aggregated plain-text record rides DEFAULT -- DETAIL is off-label
    // for text and contributed to QQ rejecting the aggregated record.
    const multi = links.length > 1;
    controller.show(context, {
      previewMode: multi ? systemShare.SharePreviewMode.DEFAULT : systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    }).catch((error: BusinessError) => {
      if (ShareOut.controller === controller) {
        ShareOut.controller = undefined;
      }
      const failure = platformFailure(error);
      hilog.warn(0x0000, TAG, `share panel show failed: ${failure.code} ${failure.message}`);
      AppState.shared.toast(LAUNCH_FAILED_TOAST);
    });
  }

  // API 26 exposes no programmatic panel close; dismissal only unregisters the
  // listener and drops the held controller so a stale instance never blocks the
  // next launch. Must stay idempotent and error-swallowing (design D3).
  static dismiss(): void {
    const controller = ShareOut.controller;
    ShareOut.controller = undefined;
    if (controller === undefined) {
      return;
    }
    try {
      controller.off('dismiss', ShareOut.onPanelDismissed);
    } catch (error) {
      // Late or repeated dismissal must stay harmless.
    }
  }
}
