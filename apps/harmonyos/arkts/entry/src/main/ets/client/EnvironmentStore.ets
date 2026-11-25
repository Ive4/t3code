import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

export interface SavedEnvironment {
  environmentId: string;
  label: string;
  origin: string;
  token?: string;
  accountId?: string;
  enabled?: boolean;
  routeId?: string;
}

export interface EnvironmentSummary {
  key: string;
  environmentId: string;
  label: string;
  origin: string;
  managed: boolean;
  enabled: boolean;
}

interface EnvironmentState {
  version: number;
  activeKey: string;
  sessions: SavedEnvironment[];
}

function isSavedEnvironment(value: SavedEnvironment): boolean {
  return !!value && typeof value.environmentId === 'string' && !!value.environmentId &&
    typeof value.label === 'string' && typeof value.origin === 'string' && !!value.origin &&
    (value.enabled === undefined || typeof value.enabled === 'boolean') &&
    (value.accountId === undefined
      ? typeof value.token === 'string' && !!value.token &&
        (value.routeId === undefined || typeof value.routeId === 'string' && !!value.routeId)
      : typeof value.accountId === 'string' && !!value.accountId &&
        value.token === undefined && value.routeId === undefined);
}

function keyOf(session: SavedEnvironment): string {
  if (session.accountId !== undefined) return 'managed:' + JSON.stringify([session.accountId, session.environmentId]);
  if (session.routeId !== undefined) return 'direct-route:' + JSON.stringify([session.environmentId, session.routeId]);
  return 'direct:' + session.environmentId;
}

function visible(session: SavedEnvironment, accountId?: string): boolean {
  return session.accountId === undefined || session.accountId === accountId;
}

export function summarizeEnvironment(session: SavedEnvironment): EnvironmentSummary {
  return {
    key: keyOf(session),
    environmentId: session.environmentId,
    label: session.label,
    origin: session.origin,
    managed: session.accountId !== undefined,
    enabled: session.enabled !== false,
  };
}

function selected(state: EnvironmentState, accountId?: string): SavedEnvironment | undefined {
  return state.sessions.find((session) => keyOf(session) === state.activeKey &&
    session.enabled !== false && visible(session, accountId)) ??
    state.sessions.find((session) => session.enabled !== false && session.accountId === undefined);
}

function savedRoute(state: EnvironmentState, key: string, accountId?: string): SavedEnvironment {
  const session = state.sessions.find((entry) => keyOf(entry) === key && visible(entry, accountId));
  if (!session) throw new Error('找不到已保存的环境。');
  return session;
}

function visibleRoutes(state: EnvironmentState, environmentId: string, accountId?: string): SavedEnvironment[] {
  return state.sessions.filter((entry) => entry.environmentId === environmentId && visible(entry, accountId));
}

function clearSelection(state: EnvironmentState, session: SavedEnvironment): void {
  state.activeKey = '';
  const fallback = state.sessions.find((entry) => entry.environmentId === session.environmentId &&
    entry.accountId === undefined && entry.enabled !== false) ?? selected(state, session.accountId);
  if (fallback) state.activeKey = keyOf(fallback);
}

export class EnvironmentStore {
  private context: common.UIAbilityContext;
  private opening: Promise<relationalStore.RdbStore> | undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private database(): Promise<relationalStore.RdbStore> {
    if (this.opening === undefined) {
      const config: relationalStore.StoreConfig = {
        name: 'arkts-environment.db',
        securityLevel: relationalStore.SecurityLevel.S3,
        encrypt: true,
      };
      this.opening = relationalStore.getRdbStore(this.context, config).then(async (database) => {
        await database.executeSql('CREATE TABLE IF NOT EXISTS environment (id INTEGER PRIMARY KEY, document TEXT NOT NULL)');
        return database;
      }).catch(() => {
        this.opening = undefined;
        throw new Error('无法打开本机加密连接存储。');
      });
    }
    return this.opening;
  }

  private async read(): Promise<EnvironmentState> {
    const result = await (await this.database()).querySql('SELECT document FROM environment WHERE id = 1');
    try {
      if (!result.goToFirstRow()) return { version: 2, activeKey: '', sessions: [] };

      const document = result.getString(0);
      const state = JSON.parse(document) as EnvironmentState;
      if (state && state.version === 2 && typeof state.activeKey === 'string' &&
        Array.isArray(state.sessions) && state.sessions.every(isSavedEnvironment)) {
        return state;
      }

      // The first ArkTS preview stored a single direct session at id = 1.
      const legacy = JSON.parse(document) as SavedEnvironment;
      if (isSavedEnvironment(legacy) && legacy.accountId === undefined) {
        return { version: 2, activeKey: keyOf(legacy), sessions: [legacy] };
      }
      throw new Error('保存的环境连接无效。');
    } finally {
      result.close();
    }
  }

  private async write(state: EnvironmentState): Promise<void> {
    const database = await this.database();
    await database.insert('environment', { id: 1, document: JSON.stringify(state) },
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async list(accountId?: string): Promise<EnvironmentSummary[]> {
    const state = await this.read();
    return state.sessions.filter((session) => visible(session, accountId)).map(summarizeEnvironment);
  }

  async active(accountId?: string): Promise<SavedEnvironment | undefined> {
    return selected(await this.read(), accountId);
  }

  async get(key: string, accountId?: string): Promise<SavedEnvironment> {
    return savedRoute(await this.read(), key, accountId);
  }

  async getManaged(environmentId: string, accountId: string): Promise<SavedEnvironment | undefined> {
    return (await this.read()).sessions.find((entry) =>
      entry.environmentId === environmentId && entry.accountId === accountId);
  }

  async update(session: SavedEnvironment): Promise<SavedEnvironment | undefined> {
    const state = await this.read();
    const key = keyOf(session);
    if (session.accountId === undefined && state.sessions.some((entry) => entry.accountId === undefined &&
      entry.environmentId === session.environmentId && entry.origin === session.origin && keyOf(entry) !== key)) {
      throw new Error('此环境已保存该地址的线路。');
    }
    state.sessions = state.sessions.map((entry) => keyOf(entry) === key ? session : entry);
    if (state.activeKey === key && session.enabled === false) clearSelection(state, session);
    await this.write(state);
    return selected(state, session.accountId);
  }

  async saveAndSelect(session: SavedEnvironment): Promise<void> {
    const state = await this.read();
    const key = keyOf(session);
    const index = state.sessions.findIndex((entry) => keyOf(entry) === key);
    if (index >= 0) state.sessions[index] = session;
    else if (visibleRoutes(state, session.environmentId, session.accountId).length > 0) state.sessions.push(session);
    else state.sessions.unshift(session);
    state.activeKey = key;
    await this.write(state);
  }

  async savePairedDirect(session: SavedEnvironment, activate: boolean): Promise<SavedEnvironment> {
    if (!isSavedEnvironment(session) || session.accountId !== undefined) throw new Error('配对的直连线路无效。');
    const state = await this.read();
    const directRoutes = visibleRoutes(state, session.environmentId);
    const existing = directRoutes.find((entry) => entry.origin === session.origin);
    const saved: SavedEnvironment = {
      environmentId: session.environmentId,
      label: existing?.label ?? session.label,
      origin: session.origin,
      token: session.token,
      routeId: existing ? existing.routeId : directRoutes.length > 0 ? util.generateRandomUUID() : undefined,
      enabled: activate ? undefined : existing?.enabled,
    };
    if (existing) state.sessions[state.sessions.indexOf(existing)] = saved;
    else if (activate && directRoutes.length === 0) state.sessions.unshift(saved);
    else state.sessions.push(saved);
    if (activate) state.activeKey = keyOf(saved);
    await this.write(state);
    return saved;
  }

  async moveRoute(key: string, delta: number, accountId?: string): Promise<void> {
    const state = await this.read();
    const session = savedRoute(state, key, accountId);
    if (delta !== -1 && delta !== 1) return;
    const routes = visibleRoutes(state, session.environmentId, accountId);
    const neighbor = routes[routes.indexOf(session) + delta];
    if (!neighbor) return;
    const index = state.sessions.indexOf(session);
    state.sessions[state.sessions.indexOf(neighbor)] = session;
    state.sessions[index] = neighbor;
    await this.write(state);
  }

  async remove(key: string, accountId?: string): Promise<SavedEnvironment | undefined> {
    return this.removeSaved(key, accountId, false);
  }

  async removeRoute(key: string, accountId?: string, replacementKey?: string): Promise<SavedEnvironment | undefined> {
    return this.removeSaved(key, accountId, true, replacementKey);
  }

  private async removeSaved(key: string, accountId: string | undefined,
    keepRoute: boolean, replacementKey?: string): Promise<SavedEnvironment | undefined> {
    const state = await this.read();
    const session = savedRoute(state, key, accountId);
    if (keepRoute && visibleRoutes(state, session.environmentId, accountId).length < 2) {
      throw new Error('无法移除环境的最后一条线路。');
    }
    if (replacementKey) {
      const replacement = savedRoute(state, replacementKey, accountId);
      if (replacement === session || replacement.environmentId !== session.environmentId || replacement.enabled === false) {
        throw new Error('备用线路已不可用。');
      }
    }
    state.sessions.splice(state.sessions.indexOf(session), 1);
    if (state.activeKey === key) {
      if (keepRoute) state.activeKey = replacementKey ?? '';
      else clearSelection(state, session);
    }
    await this.write(state);
    return selected(state, accountId);
  }

  async removeAccount(accountId: string): Promise<void> {
    const state = await this.read();
    const removingActive = state.sessions.some((session) =>
      session.accountId === accountId && keyOf(session) === state.activeKey);
    state.sessions = state.sessions.filter((session) => session.accountId !== accountId);
    if (removingActive) state.activeKey = '';
    await this.write(state);
  }
}
