export interface IncomingSharePayload {
  text: string;
  uris: string[];
  mimeType: string;
}

const SHARE_ACTIONS = new Set<string>([
  'ohos.want.action.sendData',
  'ohos.want.action.sendMultipleData',
]);

function readStringParam(
  parameters: Record<string, Object | undefined>,
  keys: string[],
): string {
  for (const key of keys) {
    const value = parameters[key];
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed.length > 0) {
        return trimmed;
      }
    }
  }
  return '';
}

function appendUri(target: string[], seen: Set<string>, candidate?: Object): void {
  if (typeof candidate !== 'string') return;
  const trimmed = candidate.trim();
  if (trimmed.length === 0 || seen.has(trimmed)) return;
  seen.add(trimmed);
  target.push(trimmed);
}

function appendUriList(target: string[], seen: Set<string>, value?: Object): void {
  if (typeof value === 'string') {
    appendUri(target, seen, value);
    return;
  }
  if (Array.isArray(value)) {
    const items = value as Object[];
    for (let i = 0; i < items.length; i += 1) {
      appendUri(target, seen, items[i]);
    }
  }
}

export function parseIncomingShareWant(
  action: string,
  parameters: Record<string, Object | undefined>,
  uri?: string,
): IncomingSharePayload | null {
  if (typeof action !== 'string' || !SHARE_ACTIONS.has(action.trim())) {
    return null;
  }
  const params: Record<string, Object | undefined> =
    parameters && typeof parameters === 'object' && !Array.isArray(parameters) ? parameters : {};

  const text = readStringParam(params, [
    'ability.params.text',
    'text',
    'content',
    'description',
  ]);

  const uris: string[] = [];
  const seenUris = new Set<string>();
  appendUri(uris, seenUris, uri);
  appendUriList(uris, seenUris, params['ability.params.stream']);
  appendUriList(uris, seenUris, params['stream']);
  appendUriList(uris, seenUris, params['uris']);
  appendUriList(uris, seenUris, params['uri']);

  if (text.length === 0 && uris.length === 0) {
    return null;
  }

  let mimeType = readStringParam(params, [
    'ability.params.mimeType',
    'mimeType',
    'type',
  ]);
  if (mimeType.length === 0 && text.length > 0 && uris.length === 0) {
    mimeType = 'text/plain';
  }

  return {
    text,
    uris,
    mimeType,
  };
}

export function mergeShareIntoDraft(existingDraft: string, shareText: string): string {
  const existing = typeof existingDraft === 'string' ? existingDraft : '';
  const incoming = typeof shareText === 'string' ? shareText.trim() : '';
  if (incoming.length === 0) {
    return existing;
  }
  if (existing.trim().length === 0) {
    return incoming;
  }
  const trimmedEnd = existing.replace(/\s+$/, '');
  return `${trimmedEnd}\n\n${incoming}`;
}
