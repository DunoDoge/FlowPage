import { ArticleDocument } from './Article';
import { Bookmark } from './Bookmark';

export enum ReadingMode {
  READER = 0,
  BROWSER = 1
}

@ObservedV2
export class ReadingEntry {
  @Trace url: string = '';
  @Trace title: string = '';
  @Trace article: ArticleDocument = new ArticleDocument();
  @Trace articleUrl: string = '';
  @Trace mode: number = ReadingMode.READER;
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace transient: boolean = true;
  @Trace position: number = -1;
  @Trace savedOnce: boolean = false;
  @Trace bookmark: Bookmark = new Bookmark();
  bookmarkId: string = '';
  // compact article form while the entry is not the current reading layer
  compact: string = '';
}

export class ReadingSeed {
  mode: number = ReadingMode.READER;
  url: string = '';
  title: string = '';
  article: ArticleDocument = new ArticleDocument();
  bookmark: Bookmark = new Bookmark();
  bookmarkId: string = '';
  transient: boolean = true;
  autoLoad: boolean = false;
}
