import webDavXmlTest from './WebDavXml.test'
import syncPlannerTest from './SyncPlanner.test'
import syncStoreTest from './SyncStore.test'

export default function testsuite() {
  webDavXmlTest()
  syncPlannerTest()
  syncStoreTest()
}
