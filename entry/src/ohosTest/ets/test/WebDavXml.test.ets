import { describe, it, expect } from '@ohos/hypium';
import { WebDavXml } from '../../../main/ets/core/sync/WebDavXml';

const SINGLE_ITEM: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:multistatus xmlns:D="DAV:">' +
  '<D:response>' +
  '<D:href>/dav/FlowPage/v1/items/aaaaaaaa.json</D:href>' +
  '<D:propstat><D:prop><D:getETag>"etag-1"</D:getETag></D:prop></D:propstat>' +
  '</D:response>' +
  '</D:multistatus>';

const ITEM_WITHOUT_ETAG: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:multistatus xmlns:D="DAV:">' +
  '<D:response>' +
  '<D:href>/dav/FlowPage/v1/items/bbbbbbbb.json</D:href>' +
  '<D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat>' +
  '</D:response>' +
  '</D:multistatus>';

const COLLECTION_AND_ITEM: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:multistatus xmlns:D="DAV:">' +
  '<D:response>' +
  '<D:href>/dav/FlowPage/v1/items/</D:href>' +
  '<D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>' +
  '</D:response>' +
  '<D:response>' +
  '<D:href>/dav/FlowPage/v1/items/cccc%20cccc.json?a=1</D:href>' +
  '<D:propstat><D:prop><D:getetag>&quot;etag-2&quot;</D:getetag></D:prop></D:propstat>' +
  '</D:response>' +
  '<D:response>' +
  '<D:href>/dav/FlowPage/v1/items/readme.txt</D:href>' +
  '<D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat>' +
  '</D:response>' +
  '</D:multistatus>';

const SINGLE_STAT: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:multistatus xmlns:D="DAV:">' +
  '<D:response><D:href>/dav/FlowPage/v1/items/a.json</D:href>' +
  '<D:propstat><D:prop><D:getetag>"stat-etag"</D:getetag></D:prop></D:propstat>' +
  '</D:response>' +
  '</D:multistatus>';

export default function webDavXmlTest() {
  describe('WebDavXmlTest', () => {
    it('parsesETagWithAnyCase', 0, () => {
      expect(WebDavXml.parseEtag(SINGLE_ITEM)).assertEqual('"etag-1"');
      expect(WebDavXml.parseEtag('<D:getetag>W/"weak"</D:getetag>')).assertEqual('W/"weak"');
      expect(WebDavXml.parseEtag('<getetag>&quot;escaped&quot;</getetag>')).assertEqual('"escaped"');
    });

    it('returnsEmptyETagWhenMissing', 0, () => {
      expect(WebDavXml.parseEtag(ITEM_WITHOUT_ETAG)).assertEqual('');
      expect(WebDavXml.parseEtag('')).assertEqual('');
    });

    it('parsesETagFromDepthZeroStat', 0, () => {
      expect(WebDavXml.parseEtag(SINGLE_STAT)).assertEqual('"stat-etag"');
    });

    it('parsesListedItemsAndSkipsCollections', 0, () => {
      const items = WebDavXml.parseItems(COLLECTION_AND_ITEM);
      expect(items.length).assertEqual(1);
      expect(items[0].name).assertEqual('cccc cccc');
      expect(items[0].etag).assertEqual('"etag-2"');
    });

    it('keepsEmptyETagForListedItemWithoutTag', 0, () => {
      const items = WebDavXml.parseItems(ITEM_WITHOUT_ETAG);
      expect(items.length).assertEqual(1);
      expect(items[0].name).assertEqual('bbbbbbbb');
      expect(items[0].etag).assertEqual('');
    });

    it('returnsNoItemsForEmptyResponse', 0, () => {
      expect(WebDavXml.parseItems('').length).assertEqual(0);
    });
  });
}
