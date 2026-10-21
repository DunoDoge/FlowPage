import webDavXmlTest from './WebDavXml.test'
import syncPlannerTest from './SyncPlanner.test'
import syncEngineTest from './SyncEngine.test'
import syncStoreTest from './SyncStore.test'

export default function testsuite() {
  webDavXmlTest()
  syncPlannerTest()
  syncEngineTest()
  syncStoreTest()
}
