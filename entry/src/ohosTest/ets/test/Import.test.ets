import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { BookmarkHtmlParser } from '../../../main/ets/core/parser/BookmarkHtmlParser';
import { FlowRepository, ImportOptions } from '../../../main/ets/repository/FlowRepository';
import { ImportResult } from '../../../main/ets/model/ImportResult';
import { BookmarkSource } from '../../../main/ets/common/Constants';
import { hilog } from '@kit.PerformanceAnalysisKit';

function buildHtml(count: number, prefix: string, folder: string): string {
  let html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n';
  if (folder.length > 0) {
    html += `<DT><H3>${folder}</H3>\n<DL><p>\n`;
  }
  for (let i = 0; i < count; i++) {
    html += `    <DT><A HREF="https://${prefix}${i}.example.com/a" ADD_DATE="1">条目 ${i}</A>\n`;
  }
  if (folder.length > 0) {
    html += '</DL><p>\n';
  }
  html += '</DL><p>\n';
  return html;
}

function importOptions(): ImportOptions {
  const options = new ImportOptions();
  options.keepFolders = true;
  options.onProgress = (done: number, total: number) => {};
  options.shouldCancel = () => false;
  return options;
}

export default function importTest() {
  describe('ImportTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_import_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('countsInvalidAndDuplicateAnchors', 0, () => {
      const html = '<DL><p>\n' +
        '<DT><A HREF="https://example.com/one">一</A>\n' +
        '<DT><A HREF="https://example.com/one">重复</A>\n' +
        '<DT><A HREF="javascript:alert(1)">坏链接</A>\n' +
        '</DL><p>\n';
      const parsed = BookmarkHtmlParser.parseAll(html);
      expect(parsed.items.length).assertEqual(1);
      expect(parsed.inFileDuplicates).assertEqual(1);
      expect(parsed.invalidCount).assertEqual(1);
      expect(parsed.invalidUrls.length).assertEqual(1);
    });

    it('previewsBeforeWriting', 0, async () => {
      const existing = Bookmark.create('https://preview0.example.com/a', '已存在', BookmarkSource.MANUAL);
      await new BookmarkDao().insert(existing);
      const html = buildHtml(3, 'preview', '收藏夹');
      const preview = await FlowRepository.get().previewHtml(html);
      expect(preview.total).assertEqual(3);
      expect(preview.duplicateCount).assertEqual(1);
      expect(preview.importable).assertEqual(2);
      expect(preview.folderCount).assertEqual(1);
      expect((await new BookmarkDao().listAll(false)).length).assertEqual(1);
    });

    it('importsInTransactionBatches', 0, async () => {
      const html = buildHtml(250, 'batch', '收件箱');
      const result = await FlowRepository.get().importHtml(html, importOptions());
      expect(result.imported).assertEqual(250);
      expect(result.failed).assertEqual(0);
      expect(result.skipped).assertEqual(0);
      const all = await new BookmarkDao().listAll(false);
      expect(all.length).assertEqual(250);
      if (all.length > 0) {
        expect(all[0].tags.length).assertEqual(1);
        expect(all[0].tags[0]).assertEqual('收件箱');
      }
    });

    it('skipsDuplicatesOnSecondImport', 0, async () => {
      const html = buildHtml(30, 'twice', '收件箱');
      const first = await FlowRepository.get().importHtml(html, importOptions());
      expect(first.imported).assertEqual(30);
      const second = await FlowRepository.get().importHtml(html, importOptions());
      expect(second.imported).assertEqual(0);
      expect(second.skipped).assertEqual(30);
      expect((await new BookmarkDao().listAll(false)).length).assertEqual(30);
    });

    it('supportsCancellation', 0, async () => {
      const html = buildHtml(100, 'cancel', '');
      const options = new ImportOptions();
      options.keepFolders = true;
      let calls = 0;
      options.shouldCancel = () => {
        calls = calls + 1;
        return calls > 10;
      };
      const result: ImportResult = await FlowRepository.get().importHtml(html, options);
      expect(result.cancelled).assertTrue();
      expect(result.imported < 100).assertTrue();
      expect((await new BookmarkDao().listAll(false)).length).assertEqual(result.imported);
    });

    it('recordsFailedUrlsForExport', 0, async () => {
      const html = '<DL><p>\n' +
        '<DT><A HREF="https://ok.example.com/a">好</A>\n' +
        '<DT><A HREF="mailto:someone@example.com">邮件</A>\n' +
        '</DL><p>\n';
      const result = await FlowRepository.get().importHtml(html, importOptions());
      expect(result.imported).assertEqual(1);
      expect(result.failed).assertEqual(1);
      expect(result.failedUrls.length).assertEqual(1);
      expect(result.failedUrls[0].indexOf('mailto') >= 0).assertTrue();
    });

    it('importsFiveThousandWithinBudget', 0, async () => {
      const html = buildHtml(5000, 'bulk', '收件箱');
      const parsed = BookmarkHtmlParser.parseAll(html);
      expect(parsed.items.length).assertEqual(5000);
      const started = Date.now();
      const result = await FlowRepository.get().importHtml(html, importOptions());
      const elapsed = Date.now() - started;
      hilog.info(0x0000, 'flowpage', 'bench import 5000 elapsed=%{public}dms', elapsed);
      expect(result.imported).assertEqual(5000);
      expect(elapsed < 12000).assertTrue();
    });
  });
}
