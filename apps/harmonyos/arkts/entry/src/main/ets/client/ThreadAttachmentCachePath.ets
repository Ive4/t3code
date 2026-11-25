import { fileIo } from '@kit.CoreFileKit';

export async function threadAttachmentCachePath(uri: string, cacheDir: string): Promise<string> {
  const encodedPath = /^file:\/\/\/([^?#]+)$/.exec(uri)?.[1];
  if (!encodedPath || !cacheDir) throw new Error('附件需要先保存到应用缓存。');
  const segments = encodedPath.split('/').map((segment: string) => decodeURIComponent(segment));
  if (segments.some((segment: string) => !segment || segment === '.' || segment === '..' ||
    /[\/\\\x00-\x1f\x7f]/.test(segment))) throw new Error('附件路径无效。');
  const path = '/' + segments.join('/');
  if (!path.startsWith(cacheDir + '/')) throw new Error('附件不在应用缓存中。');
  const relative = path.slice(cacheDir.length + 1).split('/');
  let candidate = cacheDir;
  for (let index = 0; index < relative.length; index++) {
    candidate += '/' + relative[index];
    const stat = await fileIo.lstat(candidate);
    if (index === relative.length - 1 ? !stat.isFile() : !stat.isDirectory()) {
      throw new Error('附件需要是应用缓存中的普通文件。');
    }
  }
  return path;
}
