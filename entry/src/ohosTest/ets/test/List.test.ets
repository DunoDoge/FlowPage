import webDavXmlTest from './WebDavXml.test'
import syncPlannerTest from './SyncPlanner.test'
import syncEngineTest from './SyncEngine.test'
import syncStoreTest from './SyncStore.test'
import tagSyncTest from './TagSync.test'
import snapshotTest from './Snapshot.test'
import readerTest from './Reader.test'
import conflictTest from './Conflict.test'
import repositoryTest from './Repository.test'
import queryTest from './Query.test'
import importTest from './Import.test'

export default function testsuite() {
  webDavXmlTest()
  syncPlannerTest()
  syncEngineTest()
  syncStoreTest()
  tagSyncTest()
  snapshotTest()
  readerTest()
  conflictTest()
  repositoryTest()
  queryTest()
  importTest()
}
