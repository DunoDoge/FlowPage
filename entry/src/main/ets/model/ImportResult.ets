export class ImportedBookmark {
  url: string = '';
  title: string = '';
  folderPath: string = '';
}

export class ImportResult {
  total: number = 0;
  imported: number = 0;
  skipped: number = 0;
  failed: number = 0;
  failedUrls: string[] = [];
  folderCount: number = 0;
}
