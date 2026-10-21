import { describe, it, expect } from '@ohos/hypium';
import { SyncAction, SyncPlanner } from '../../../main/ets/core/sync/SyncPlanner';

export default function syncPlannerTest() {
  describe('SyncPlannerTest', () => {
    it('skipsUnchangedBookmarkOnSecondSync', 0, () => {
      expect(SyncPlanner.planForExisting(false, '"e1"', '"e1"')).assertEqual(SyncAction.SKIP);
    });

    it('uploadsDirtyBookmarkWithSameETag', 0, () => {
      expect(SyncPlanner.planForExisting(true, '"e1"', '"e1"')).assertEqual(SyncAction.UPLOAD);
    });

    it('fetchesWhenRemoteETagDiffers', 0, () => {
      expect(SyncPlanner.planForExisting(false, '"e1"', '"e2"')).assertEqual(SyncAction.FETCH);
      expect(SyncPlanner.planForExisting(true, '"e1"', '"e2"')).assertEqual(SyncAction.FETCH);
    });

    it('skipsOrUploadsWhenRemoteHasNoETag', 0, () => {
      expect(SyncPlanner.planForExisting(false, '"e1"', '')).assertEqual(SyncAction.SKIP);
      expect(SyncPlanner.planForExisting(true, '"e1"', '')).assertEqual(SyncAction.UPLOAD);
      expect(SyncPlanner.planForExisting(false, '', '')).assertEqual(SyncAction.SKIP);
    });

    it('downloadsWhenRemoteIsNewer', 0, () => {
      expect(SyncPlanner.planAfterFetch(false, '"e1"', 100, 200)).assertEqual(SyncAction.DOWNLOAD);
      expect(SyncPlanner.planAfterFetch(true, '"e1"', 100, 200)).assertEqual(SyncAction.DOWNLOAD);
    });

    it('uploadsDirtyLocalWhenRemoteIsOlder', 0, () => {
      expect(SyncPlanner.planAfterFetch(true, '"e1"', 200, 100)).assertEqual(SyncAction.UPLOAD);
    });

    it('adoptsRemoteETagWhenLocalETagWasMissing', 0, () => {
      expect(SyncPlanner.planAfterFetch(false, '', 200, 100)).assertEqual(SyncAction.ADOPT_ETAG);
    });

    it('uploadsLocalWhenRemoteIsOlderAndETagKnown', 0, () => {
      expect(SyncPlanner.planAfterFetch(false, '"e1"', 200, 100)).assertEqual(SyncAction.UPLOAD);
    });

    it('uploadsLocalOnlyBookmarks', 0, () => {
      expect(SyncPlanner.planForLocalOnly(true, false)).assertEqual(SyncAction.UPLOAD);
      expect(SyncPlanner.planForLocalOnly(false, false)).assertEqual(SyncAction.UPLOAD);
      expect(SyncPlanner.planForLocalOnly(false, true)).assertEqual(SyncAction.SKIP);
    });
  });
}
