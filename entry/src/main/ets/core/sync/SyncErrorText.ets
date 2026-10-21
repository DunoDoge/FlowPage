export class SyncErrorText {
  static describe(message: string): string {
    if (message === 'AUTH_401') {
      return '账号或应用密码错误。坚果云请使用「应用密码」。';
    }
    if (message === 'AUTH_403') {
      return '账号已通过，但没有该目录的权限（403）。';
    }
    if (message === 'NOT_FOUND') {
      return '地址或目录不存在（404）。';
    }
    if (message === 'NO_CREDENTIAL') {
      return '凭据无法解密，请重新输入应用密码。';
    }
    if (message === 'NO_CONFIG') {
      return '还没有配置同步。';
    }
    if (message === 'BUSY') {
      return '上一次同步还没结束。';
    }
    if (message === 'PARENT_MISSING') {
      return '远端父目录不存在。';
    }
    if (message.startsWith('NET_')) {
      return SyncErrorText.network(message.substring(4));
    }
    if (message.startsWith('PUT_')) {
      return SyncErrorText.write(Number(message.substring(4)));
    }
    if (message.startsWith('DELETE_')) {
      return SyncErrorText.remove(Number(message.substring(7)));
    }
    if (message.startsWith('GET_')) {
      return SyncErrorText.read(Number(message.substring(4)));
    }
    if (message.startsWith('MKCOL_')) {
      return `创建远端目录失败（HTTP ${message.substring(6)}）。`;
    }
    if (message.startsWith('PROPFIND_')) {
      return `读取远端目录失败（HTTP ${message.substring(9)}）。`;
    }
    if (message.startsWith('STATUS_')) {
      return `服务器返回 HTTP ${message.substring(7)}。`;
    }
    return `同步失败：${message}`;
  }

  static describeError(error: Object): string {
    if (error instanceof Error) {
      return SyncErrorText.describe(error.message);
    }
    return '同步失败，请稍后再试。';
  }

  private static network(code: string): string {
    if (code === '2300006' || code === '2300007') {
      return '网络不可达，检查地址与网络。';
    }
    if (code === '2300028') {
      return '连接超时，稍后再试。';
    }
    return `网络请求失败（${code}）。`;
  }

  private static write(status: number): string {
    if (status === 401) {
      return '账号或应用密码错误，远端拒绝写入。';
    }
    if (status === 403) {
      return '远端拒绝写入（403），请检查目录权限。';
    }
    if (status === 409) {
      return '远端拒绝写入（409），请检查目录权限或稍后重试。';
    }
    if (status === 412) {
      return '远端已有更新的版本（412），请重试同步。';
    }
    return `远端拒绝写入（HTTP ${status}）。`;
  }

  private static remove(status: number): string {
    if (status === 401 || status === 403) {
      return `远端拒绝删除（${status}），请检查目录权限。`;
    }
    if (status === 409) {
      return '远端目录状态异常（409），暂时无法删除。';
    }
    return `远端删除失败（HTTP ${status}）。`;
  }

  private static read(status: number): string {
    if (status === 404) {
      return '远端条目已不存在（404）。';
    }
    if (status === 401 || status === 403) {
      return `远端拒绝读取（${status}），请检查目录权限。`;
    }
    return `读取远端条目失败（HTTP ${status}）。`;
  }
}
