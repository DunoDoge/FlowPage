function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function formatRelative(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const diff = Date.now() - ts;
  if (diff < 60000) {
    return '刚刚';
  }
  if (diff < 3600000) {
    return `${Math.floor(diff / 60000)} 分钟前`;
  }
  if (diff < 86400000) {
    return `${Math.floor(diff / 3600000)} 小时前`;
  }
  if (diff < 172800000) {
    return '昨天';
  }
  if (diff < 604800000) {
    return `${Math.floor(diff / 86400000)} 天前`;
  }
  const date = new Date(ts);
  return `${date.getMonth() + 1} 月 ${date.getDate()} 日`;
}

export function formatFullDate(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const date = new Date(ts);
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

