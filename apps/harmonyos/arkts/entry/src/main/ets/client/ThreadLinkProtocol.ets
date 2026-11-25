export const THREAD_LINK_STORAGE_KEY = 't3.arkts.threadLink';

export interface ThreadLinkTarget {
  readonly environmentId: string;
  readonly threadId: string;
}

const THREAD_PATH = /^t3code(?:-dev|-preview)?:\/\/threads\/([^/\\?#]+)\/([^/\\?#]+)(?:[?#].*)?$/;
const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/;

function decodeLinkId(segment: string): string | undefined {
  const id = decodeURIComponent(segment);
  return CONTROL_CHARACTER.test(id) ? undefined : id.trim();
}

export function parseThreadLink(uri: string): ThreadLinkTarget | undefined {
  if (/\s/.test(uri) || CONTROL_CHARACTER.test(uri)) return undefined;
  const match = THREAD_PATH.exec(uri);
  if (!match) return undefined;
  try {
    const environmentId = decodeLinkId(match[1]);
    const threadId = decodeLinkId(match[2]);
    if (environmentId && threadId) return { environmentId, threadId };
  } catch (_) {
    return undefined;
  }
  return undefined;
}
