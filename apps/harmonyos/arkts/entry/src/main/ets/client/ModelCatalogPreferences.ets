import { REQUEST_ID, validProviderInstanceId } from './T3Protocol';
import type { ThreadLaunchModel } from './ThreadLaunchProtocol';

export type ModelCatalogPreferenceKind = 'favorite' | 'hidden';

interface ModelCatalogReference {
  provider: string;
  model: string;
}

interface ModelCatalogProviderPreferences {
  hiddenModels: string[];
  modelOrder: string[];
}

export interface NativeModelCatalogPreferences {
  favorites: ModelCatalogReference[];
  providerModelPreferences: Record<string, ModelCatalogProviderPreferences>;
}

interface ModelCatalogSettings {
  favorites?: ModelCatalogReference[] | null;
  providerModelPreferences?: Record<string, ModelCatalogProviderPreferences> | null;
}

interface FavoriteOperation extends ModelCatalogReference {
  favorite: boolean;
}

interface HiddenOperation extends ModelCatalogReference {
  hidden: boolean;
}

interface ModelCatalogPatch {
  setModelFavorites?: FavoriteOperation[];
  setModelsHidden?: HiddenOperation[];
}

interface ModelCatalogUpdateInput {
  patch: ModelCatalogPatch;
}

interface ModelCatalogUpdateRequest {
  _tag: string;
  id: string;
  tag: string;
  payload: ModelCatalogUpdateInput;
  headers: string[][];
}

interface ModelCatalogSessionGrant {
  authenticated: boolean;
  permissions?: string[];
  scopes?: string[];
  serverUpdateScope?: string;
}

function parseModelSlug(value?: string): string {
  return typeof value === 'string' ? value.trim() : '';
}

function uniqueModelSlugs(value?: string[]): string[] {
  return Array.isArray(value) ? Array.from(new Set(value.map(parseModelSlug).filter(Boolean))) : [];
}

export function readModelCatalogPreferences(value?: Object | null): NativeModelCatalogPreferences {
  const settings = value as ModelCatalogSettings | undefined;
  const favorites: ModelCatalogReference[] = [];
  const favoriteKeys = new Set<string>();
  const savedFavorites = settings?.favorites;
  for (const entry of Array.isArray(savedFavorites) ? savedFavorites : []) {
    if (!entry || !validProviderInstanceId(entry.provider)) continue;
    const model = parseModelSlug(entry.model);
    if (!model) continue;
    const key = JSON.stringify([entry.provider, model]);
    if (favoriteKeys.has(key)) continue;
    favoriteKeys.add(key);
    favorites.push({ provider: entry.provider, model });
  }
  const providerModelPreferences: Record<string, ModelCatalogProviderPreferences> = {};
  const providers = settings?.providerModelPreferences;
  if (providers && typeof providers === 'object' && !Array.isArray(providers)) {
    for (const provider of Object.keys(providers)) {
      const entry = providers[provider];
      if (!validProviderInstanceId(provider) || !entry || typeof entry !== 'object') continue;
      providerModelPreferences[provider] = {
        hiddenModels: uniqueModelSlugs(entry.hiddenModels), modelOrder: uniqueModelSlugs(entry.modelOrder),
      };
    }
  }
  return { favorites, providerModelPreferences };
}

export function modelCatalogIsFavorite(preferences: NativeModelCatalogPreferences | undefined,
  provider: string, model: string): boolean {
  return preferences?.favorites.some((entry: ModelCatalogReference) =>
    entry.provider === provider && entry.model === model) === true;
}

export function modelCatalogIsHidden(preferences: NativeModelCatalogPreferences | undefined,
  provider: string, model: string, isCustom: boolean = false): boolean {
  return !isCustom && preferences?.providerModelPreferences[provider]?.hiddenModels?.includes(model) === true;
}

export function modelCatalogVisibleModels(models: ThreadLaunchModel[], preferences: NativeModelCatalogPreferences | undefined,
  provider: string, includeHidden: boolean, favoritesOnly: boolean = false, displayedModel: string = ''): ThreadLaunchModel[] {
  const order = preferences?.providerModelPreferences[provider]?.modelOrder ?? [];
  const rank = (slug: string): number => {
    const index = order.indexOf(slug);
    return index < 0 ? order.length : index;
  };
  return models.filter((model: ThreadLaunchModel) =>
    (includeHidden || model.slug === displayedModel || !modelCatalogIsHidden(preferences, provider, model.slug, model.isCustom)) &&
    (!favoritesOnly || modelCatalogIsFavorite(preferences, provider, model.slug)))
    .sort((left: ThreadLaunchModel, right: ThreadLaunchModel) =>
      Number(modelCatalogIsFavorite(preferences, provider, right.slug)) -
      Number(modelCatalogIsFavorite(preferences, provider, left.slug)) || rank(left.slug) - rank(right.slug));
}

export function modelCatalogSettingsWriteAllowed(session: ModelCatalogSessionGrant): boolean {
  if (session.authenticated !== true) return false;
  if (session.permissions !== undefined) {
    return Array.isArray(session.permissions) && session.permissions.includes('settings:write');
  }
  const scopes = session.scopes;
  return Array.isArray(scopes) && (scopes.includes('settings:write') ||
    (session.serverUpdateScope === undefined && scopes.includes('orchestration:operate')));
}

export function modelCatalogUpdateRequest(provider: string, rawModel: string, kind: ModelCatalogPreferenceKind,
  enabled: boolean): ModelCatalogUpdateRequest {
  const model = parseModelSlug(rawModel);
  if (!validProviderInstanceId(provider) || !model) throw new Error('请选择有效的模型。');
  const patch: ModelCatalogPatch = kind === 'favorite' ? { setModelFavorites: [{ provider, model, favorite: enabled }] }
    : { setModelsHidden: [{ provider, model, hidden: enabled }] };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.updateSettings', payload: { patch }, headers: [] };
}

export function readUpdatedModelCatalogPreferences(value: Object | undefined, provider: string, rawModel: string,
  kind: ModelCatalogPreferenceKind, enabled: boolean): NativeModelCatalogPreferences {
  const settings = value as ModelCatalogSettings | undefined;
  const hidden = settings?.providerModelPreferences;
  if (kind === 'favorite' ? !Array.isArray(settings?.favorites) :
    !hidden || typeof hidden !== 'object' || Array.isArray(hidden)) {
    throw new Error('环境未返回已保存的模型偏好。');
  }
  const result = readModelCatalogPreferences(value);
  const model = parseModelSlug(rawModel);
  const updated = kind === 'favorite' ? modelCatalogIsFavorite(result, provider, model) :
    modelCatalogIsHidden(result, provider, model);
  if (updated !== enabled) throw new Error('环境未确认模型偏好修改，请刷新后重试。');
  return result;
}
