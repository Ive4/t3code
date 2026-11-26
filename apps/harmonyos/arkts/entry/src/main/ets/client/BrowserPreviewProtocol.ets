export interface BrowserPreviewTab {
  tabId: string;
  title: string;
  url: string;
  loading: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
}

export interface BrowserPreviewState {
  tabs: BrowserPreviewTab[];
  selectedTabId: string | null;
  streaming: boolean;
  canControl: boolean;
  error: string | null;
}

export type BrowserPreviewCommand =
  | { type: 'navigate'; url: string }
  | { type: 'reload' }
  | { type: 'history'; delta: number }
  | { type: 'text'; text: string };

const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/;
const SCHEME_WITH_AUTHORITY = /^([a-zA-Z][a-zA-Z\d+.-]*):\/\//;
const EXPLICIT_SCHEME_PREFIX = /^([a-zA-Z][a-zA-Z\d+.-]*):/;
const BARE_HOST_PORT = /^[^/?#:@]+:\d+(?:[/?#]|$)/;
const LOOPBACK_PREFIX = /^(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\])(?::|\/|\?|#|$)/i;
const KNOWN_NON_WEB_SCHEMES = new Set<string>([
  'about:',
  'blob:',
  'chrome:',
  'data:',
  'file:',
  'ftp:',
  'javascript:',
  'mailto:',
  'sms:',
  'ssh:',
  'tel:',
  'vbscript:',
  'view-source:',
  'ws:',
  'wss:',
]);

function hasValidAuthority(afterScheme: string): boolean {
  if (afterScheme.length === 0) {
    return false;
  }
  const slashIndex = afterScheme.indexOf('/');
  const queryIndex = afterScheme.indexOf('?');
  const hashIndex = afterScheme.indexOf('#');
  let end = afterScheme.length;
  if (slashIndex >= 0 && slashIndex < end) end = slashIndex;
  if (queryIndex >= 0 && queryIndex < end) end = queryIndex;
  if (hashIndex >= 0 && hashIndex < end) end = hashIndex;
  const authority = afterScheme.slice(0, end);
  if (authority.length === 0) {
    return false;
  }
  const atIndex = authority.lastIndexOf('@');
  const hostPort = atIndex >= 0 ? authority.slice(atIndex + 1) : authority;
  if (hostPort.length === 0 || hostPort.startsWith(':')) {
    return false;
  }
  return true;
}

export function normalizeBrowserPreviewUrl(input: string): string | null {
  if (typeof input !== 'string' || CONTROL_CHARACTER.test(input)) {
    return null;
  }
  const trimmed = input.trim();
  if (trimmed.length === 0 || /\s/.test(trimmed)) {
    return null;
  }

  const authorityMatch = SCHEME_WITH_AUTHORITY.exec(trimmed);
  if (authorityMatch !== null) {
    const scheme = authorityMatch[1].toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return null;
    }
    const rest = trimmed.slice(authorityMatch[0].length);
    if (!hasValidAuthority(rest)) {
      return null;
    }
    return `${scheme}://${rest}`;
  }

  const schemeMatch = EXPLICIT_SCHEME_PREFIX.exec(trimmed);
  if (schemeMatch !== null) {
    const protocol = `${schemeMatch[1].toLowerCase()}:`;
    if (KNOWN_NON_WEB_SCHEMES.has(protocol) || !BARE_HOST_PORT.test(trimmed)) {
      return null;
    }
  }

  if (!hasValidAuthority(trimmed)) {
    return null;
  }

  const scheme = LOOPBACK_PREFIX.test(trimmed) ? 'http' : 'https';
  return `${scheme}://${trimmed}`;
}

export function selectBrowserPreviewTab(
  state: BrowserPreviewState,
  tabId: string,
): BrowserPreviewState {
  if (typeof tabId !== 'string' || tabId.length === 0) {
    return state;
  }
  let exists = false;
  for (let i = 0; i < state.tabs.length; i += 1) {
    if (state.tabs[i].tabId === tabId) {
      exists = true;
      break;
    }
  }
  if (!exists || state.selectedTabId === tabId) {
    return state;
  }
  return {
    tabs: state.tabs,
    selectedTabId: tabId,
    streaming: state.streaming,
    canControl: state.canControl,
    error: state.error,
  };
}

export function buildBrowserCommandPayload(command: BrowserPreviewCommand): string {
  if (command.type === 'navigate') {
    const url = normalizeBrowserPreviewUrl(command.url);
    if (url === null) {
      throw new Error('Invalid browser preview navigate URL.');
    }
    return JSON.stringify({
      type: 'navigate',
      url,
    });
  }
  if (command.type === 'reload') {
    return JSON.stringify({
      type: 'reload',
    });
  }
  if (command.type === 'history') {
    if (typeof command.delta !== 'number' || !Number.isFinite(command.delta)) {
      throw new Error('Invalid browser preview history delta.');
    }
    return JSON.stringify({
      type: 'history',
      delta: command.delta,
    });
  }
  if (command.type === 'text') {
    if (typeof command.text !== 'string') {
      throw new Error('Invalid browser preview text command.');
    }
    return JSON.stringify({
      type: 'text',
      text: command.text,
    });
  }
  throw new Error('Unsupported browser preview command.');
}
