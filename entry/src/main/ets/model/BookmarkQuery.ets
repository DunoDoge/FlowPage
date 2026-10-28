import { StreamFilter } from '../common/Constants';
import { Bookmark } from './Bookmark';

export enum BookmarkSort {
  CREATED_DESC = 0,
  DOMAIN_ASC = 1,
  CREATED_ASC = 2
}

export class BookmarkQuery {
  filter: number = StreamFilter.ALL;
  tag: string = '';
  keyword: string = '';
  sort: number = BookmarkSort.CREATED_DESC;
  // Direct-membership filter: '' = no folder constraint, otherwise exact folder_id match.
  folderId: string = '';
}

export class BookmarkPage {
  items: Bookmark[] = [];
  hasMore: boolean = false;
}
