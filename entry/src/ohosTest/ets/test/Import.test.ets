import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { FolderDao } from '../../../main/ets/core/db/FolderDao';
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

    it('importsWithoutDerivingTags', 0, async () => {
      const html = buildHtml(250, 'batch', '收件箱');
      const result = await FlowRepository.get().importHtml(html, importOptions());
      expect(result.imported).assertEqual(250);
      expect(result.failed).assertEqual(0);
      expect(result.skipped).assertEqual(0);
      const all = await new BookmarkDao().listAll(false);
      expect(all.length).assertEqual(250);
      if (all.length > 0) {
        expect(all[0].tags.length).assertEqual(0);
        expect(all[0].folderId.length > 0).assertTrue();
      }
      const tree = await FlowRepository.get().folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('收件箱');
      expect(tree[0].totalCount).assertEqual(250);
      const tags = await FlowRepository.get().listTags();
      expect(tags.length).assertEqual(0);
    });

    it('buildsNestedFolderChain', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3>书签栏</H3>\n<DL><p>\n' +
        '<DT><H3>开发</H3>\n<DL><p>\n' +
        '<DT><H3>前端</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://nested.example.com/a" ADD_DATE="1700000000">嵌套条目</A>\n' +
        '</DL><p>\n</DL><p>\n</DL><p>\n</DL><p>\n';
      const result = await FlowRepository.get().importHtml(html, importOptions());
      expect(result.imported).assertEqual(1);
      const tree = await FlowRepository.get().folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('书签栏');
      expect(tree[0].children.length).assertEqual(1);
      expect(tree[0].children[0].folder.name).assertEqual('开发');
      expect(tree[0].children[0].children.length).assertEqual(1);
      const leaf = tree[0].children[0].children[0];
      expect(leaf.folder.name).assertEqual('前端');
      expect(leaf.totalCount).assertEqual(1);
      const all = await new BookmarkDao().listAll(false);
      expect(all.length).assertEqual(1);
      expect(all[0].folderId).assertEqual(leaf.folder.id);
    });

    it('mergesSameNameSiblings', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3>相同</H3>\n<DL><p>\n<DT><A HREF="https://one.example.com/a">一</A>\n</DL><p>\n' +
        '<DT><H3>相同</H3>\n<DL><p>\n<DT><A HREF="https://two.example.com/a">二</A>\n</DL><p>\n' +
        '</DL><p>\n';
      const result = await FlowRepository.get().importHtml(html, importOptions());
      expect(result.imported).assertEqual(2);
      const tree = await FlowRepository.get().folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('相同');
      expect(tree[0].totalCount).assertEqual(2);
    });

    it('keepsAddDateAsCreatedAt', 0, () => {
      const html = '<DL><p>\n' +
        '<DT><A HREF="https://date.example.com/a" ADD_DATE="1700000000">有日期</A>\n' +
        '<DT><A HREF="https://nodate.example.com/a">无日期</A>\n' +
        '</DL><p>\n';
      const parsed = BookmarkHtmlParser.parseAll(html);
      expect(parsed.items.length).assertEqual(2);
      expect(parsed.items[0].addedAt).assertEqual(1700000000000);
      expect(parsed.items[1].addedAt).assertEqual(0);
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

    it('exportRebuildsNestedStructure', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><A HREF="https://root.example.com/a" ADD_DATE="1690000000">根级书签</A>\n' +
        '<DT><H3>书签栏</H3>\n<DL><p>\n' +
        '<DT><H3>开发</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://nested.example.com/a" ADD_DATE="1700000000">嵌套书签</A>\n' +
        '</DL><p>\n</DL><p>\n</DL><p>\n';
      await FlowRepository.get().importHtml(html, importOptions());
      const exported = await FlowRepository.get().exportHtml();
      const parsed = BookmarkHtmlParser.parseAll(exported);
      expect(parsed.items.length).assertEqual(2);
      let nestedPath = '';
      let rootPath = 'unset';
      for (let i = 0; i < parsed.items.length; i++) {
        if (parsed.items[i].url.indexOf('nested.example.com') >= 0) {
          nestedPath = parsed.items[i].segments.join('/');
        }
        if (parsed.items[i].url.indexOf('root.example.com') >= 0) {
          rootPath = parsed.items[i].segments.join('/');
        }
      }
      expect(nestedPath).assertEqual('书签栏/开发');
      expect(rootPath).assertEqual('');
    });

    it('roundTripKeepsBrowserSemanticMarkers', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3 ADD_DATE="1" PERSONAL_TOOLBAR_FOLDER="true">书签栏</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://bar.example.com/a">栏内书签</A>\n' +
        '<DT><H3 PERSONAL_TOOLBAR_FOLDER="true">深层</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://deep.example.com/a">深层书签</A>\n' +
        '</DL><p>\n</DL><p>\n' +
        '<DT><H3 UNFILED_BOOKMARKS_FOLDER="true">其他书签</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://unfiled.example.com/a">其他书签成员</A>\n' +
        '</DL><p>\n</DL><p>\n</DL><p>\n';
      await FlowRepository.get().importHtml(html, importOptions());
      const exported = await FlowRepository.get().exportHtml();
      expect(exported.indexOf('PERSONAL_TOOLBAR_FOLDER="true">书签栏<') >= 0).assertTrue();
      expect(exported.indexOf('UNFILED_BOOKMARKS_FOLDER="true">其他书签<') >= 0).assertTrue();
      // Deep folders with a source marker stay plain: markers only apply at
      // the root level and must not be re-emitted one level down.
      expect(exported.indexOf('PERSONAL_TOOLBAR_FOLDER="true">深层<') < 0).assertTrue();
      const parsed = BookmarkHtmlParser.parseAll(exported);
      expect(parsed.topMarks.get('书签栏')).assertEqual('toolbar');
      expect(parsed.topMarks.get('其他书签')).assertEqual('unfiled');
      expect(parsed.topMarks.has('深层')).assertFalse();
    });

    it('secondImportKeepsFolderRowSyncSilent', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3 PERSONAL_TOOLBAR_FOLDER="true">书签栏</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://idem.example.com/a">幂等书签</A>\n' +
        '</DL><p>\n</DL><p>\n';
      await FlowRepository.get().importHtml(html, importOptions());
      const folderDao = new FolderDao();
      const before = await folderDao.findByParentAndName('', '书签栏');
      expect(before === undefined).assertFalse();
      if (before === undefined) {
        return;
      }
      expect(before.kind).assertEqual('toolbar');
      await folderDao.setKind(before.id, 'toolbar');
      const afterSameKind = await folderDao.findByParentAndName('', '书签栏');
      expect(afterSameKind === undefined).assertFalse();
      if (afterSameKind !== undefined) {
        expect(afterSameKind.rev).assertEqual(before.rev);
        expect(afterSameKind.updatedAt).assertEqual(before.updatedAt);
      }
      await FlowRepository.get().importHtml(html, importOptions());
      const after = await folderDao.findByParentAndName('', '书签栏');
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.rev).assertEqual(before.rev);
        expect(after.updatedAt).assertEqual(before.updatedAt);
        expect(after.kind).assertEqual('toolbar');
      }
    });

    it('roundTripRestoresAddDateOrderWithinFolder', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3>排序</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://order.example.com/three" ADD_DATE="3000">三</A>\n' +
        '<DT><A HREF="https://order.example.com/one" ADD_DATE="1000">一</A>\n' +
        '<DT><A HREF="https://order.example.com/two" ADD_DATE="2000">二</A>\n' +
        '</DL><p>\n</DL><p>\n';
      await FlowRepository.get().importHtml(html, importOptions());
      const exported = await FlowRepository.get().exportHtml();
      const parsed = BookmarkHtmlParser.parseAll(exported);
      expect(parsed.items.length).assertEqual(3);
      if (parsed.items.length === 3) {
        expect(parsed.items[0].url.indexOf('order.example.com/one') >= 0).assertTrue();
        expect(parsed.items[1].url.indexOf('order.example.com/two') >= 0).assertTrue();
        expect(parsed.items[2].url.indexOf('order.example.com/three') >= 0).assertTrue();
        expect(parsed.items[0].segments.join('/')).assertEqual('排序');
      }
    });

    it('exportKeepsSlashFolderNameLiteral', 0, async () => {
      const html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n' +
        '<DT><H3>AI/ML</H3>\n<DL><p>\n' +
        '<DT><A HREF="https://slash.example.com/a">斜杠名成员</A>\n' +
        '</DL><p>\n</DL><p>\n';
      await FlowRepository.get().importHtml(html, importOptions());
      const tree = await FlowRepository.get().folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('AI/ML');
      expect(tree[0].children.length).assertEqual(0);
      expect(tree[0].totalCount).assertEqual(1);
      const exported = await FlowRepository.get().exportHtml();
      const parsed = BookmarkHtmlParser.parseAll(exported);
      expect(parsed.items.length).assertEqual(1);
      expect(parsed.items[0].segments.join('/')).assertEqual('AI/ML');
    });

    it('exportOmitsTagsAndDanglingFallsToRoot', 0, async () => {
      const bookmark = Bookmark.create('https://tagged.example.com/a', '带标签', BookmarkSource.MANUAL);
      bookmark.tags = ['私藏'];
      bookmark.folderId = 'ghost-folder';
      bookmark.rebuildSearch();
      await new BookmarkDao().insert(bookmark);
      const exported = await FlowRepository.get().exportHtml();
      expect(exported.indexOf('私藏') < 0).assertTrue();
      expect(exported.indexOf('ghost-folder') < 0).assertTrue();
      const parsed = BookmarkHtmlParser.parseAll(exported);
      expect(parsed.items.length).assertEqual(1);
      expect(parsed.items[0].segments.join('/')).assertEqual('');
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
