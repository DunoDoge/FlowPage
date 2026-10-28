export class ImportedBookmark {
  url: string = '';
  title: string = '';
  folderPath: string = '';
  segments: string[] = [];
  addedAt: number = 0;
}

export class ImportResult {
  total: number = 0;
  imported: number = 0;
  skipped: number = 0;
  failed: number = 0;
  cancelled: boolean = false;
  failedUrls: string[] = [];
  folderCount: number = 0;
}
