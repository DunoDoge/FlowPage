import { describe, it, expect } from '@ohos/hypium';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { ShareLink, buildShareRecords, buildAggregatedRecord } from '../../../main/ets/common/ShareOut';
import { shareLinkOf, shareLinkTargetOf } from '../../../main/ets/common/ShareUtil';

function link(url: string, title: string, description: string): ShareLink {
  const item = new ShareLink();
  item.url = url;
  item.title = title;
  item.description = description;
  return item;
}

export default function shareOutTest() {
  describe('ShareOutTest', () => {
    it('fallsBackToUrlWhenTitleMissing', 0, () => {
      const records = buildShareRecords([link('https://example.com/a', '', '摘要')]);
      expect(records.length).assertEqual(1);
      expect(records[0].title).assertEqual('https://example.com/a');
      expect(records[0].content).assertEqual('https://example.com/a');
      expect(records[0].description).assertEqual('摘要');
    });

    it('keepsTrimmedTitleWhenPresent', 0, () => {
      const records = buildShareRecords([link('https://example.com/a', '  标题  ', '摘要')]);
      expect(records[0].title).assertEqual('标题');
    });

    it('buildsOneRecordPerLinkInOrder', 0, () => {
      const records = buildShareRecords([
        link('https://example.com/1', '一', 'd1'),
        link('https://example.com/2', '', ''),
        link('https://example.com/3', '三', 'd3')
      ]);
      expect(records.length).assertEqual(3);
      expect(records[0].content).assertEqual('https://example.com/1');
      expect(records[1].content).assertEqual('https://example.com/2');
      expect(records[1].title).assertEqual('https://example.com/2');
      expect(records[2].content).assertEqual('https://example.com/3');
      expect(records[2].title).assertEqual('三');
    });

    it('recordsCarryOnlyUrlTitleAndDescription', 0, () => {
      const records = buildShareRecords([link('https://example.com/a', '标题', '摘要')]);
      expect(records[0].utd).assertEqual(uniformTypeDescriptor.UniformDataType.HYPERLINK);
      expect(records[0].uri).assertUndefined();
      expect(records[0].label).assertUndefined();
      expect(records[0].thumbnail).assertUndefined();
      expect(records[0].thumbnailUri).assertUndefined();
      expect(records[0].extraData).assertUndefined();
    });

    it('roundTripsShareLinkTarget', 0, () => {
      // Dormant App Linking helpers (send-side wrapping resumes once the
      // dunodoge.com /s endpoint is live); round-trip keeps them honest.
      const wrapped = shareLinkOf('https://example.com/a?x=1&y=中文');
      expect(shareLinkTargetOf(wrapped)).assertEqual('https://example.com/a?x=1&y=中文');
      expect(shareLinkTargetOf('https://example.com/other')).assertEqual('');
    });

    it('aggregatedLinesAreSingleLineUrlOnly', 0, () => {
      const record = buildAggregatedRecord([
        link('https://example.com/1', '一', ''),
        link('https://example.com/2', '', '')
      ]);
      const content: string = record.content ?? '';
      expect(content).assertEqual('https://example.com/1 https://example.com/2');
      expect(content.indexOf('\n')).assertEqual(-1);
      expect(content.indexOf('一')).assertEqual(-1);
    });

    it('emptyInputProducesNoRecords', 0, () => {
      expect(buildShareRecords([]).length).assertEqual(0);
    });

    it('aggregatesMultiLinksIntoOnePlainTextRecord', 0, () => {
      const record = buildAggregatedRecord([
        link('https://example.com/1', '一', 'd1'),
        link('https://example.com/2', '', ''),
        link('https://example.com/3', '三', 'd3')
      ]);
      expect(record.utd).assertEqual(uniformTypeDescriptor.UniformDataType.PLAIN_TEXT);
      expect(record.title).assertEqual('3 条链接');
      expect(record.content).assertEqual('https://example.com/1 https://example.com/2 https://example.com/3');
      expect(record.description).assertEqual('');
    });
  });
}
