import webDavXmlTest from './WebDavXml.test'
import syncPlannerTest from './SyncPlanner.test'
import syncEngineTest from './SyncEngine.test'
import syncStoreTest from './SyncStore.test'
import tagSyncTest from './TagSync.test'
import snapshotTest from './Snapshot.test'
import readerTest from './Reader.test'
import readerSearchTest from './ReaderSearch.test'
import conflictTest from './Conflict.test'
import repositoryTest from './Repository.test'
import queryTest from './Query.test'
import importTest from './Import.test'
import folderTest from './Folder.test'
import folderDropTest from './FolderDrop.test'
import folderHomeTest from './FolderHome.test'

export default function testsuite() {
  webDavXmlTest()
  syncPlannerTest()
  syncEngineTest()
  syncStoreTest()
  tagSyncTest()
  snapshotTest()
  readerTest()
  readerSearchTest()
  conflictTest()
  repositoryTest()
  queryTest()
  importTest()
  folderTest()
  folderDropTest()
  folderHomeTest()
}
