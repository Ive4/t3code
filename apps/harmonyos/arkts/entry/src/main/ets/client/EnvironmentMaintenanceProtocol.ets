import { http } from '@kit.NetworkKit';
import { REQUEST_ID, validProviderInstanceId } from './T3Protocol';

export interface EnvironmentMaintenanceProvider {
  instanceId: string;
  driver: string;
  label: string;
  version: string;
  latestVersion?: string;
  canUpdate: boolean;
  status?: string;
  detail?: string;
}

export interface EnvironmentMaintenanceSnapshot {
  version: string;
  canCheck: boolean;
  canRefresh: boolean;
  providers: EnvironmentMaintenanceProvider[];
  organization?: string;
  updateDenial?: string;
  serverUpdateCapability?: string;
}

interface NativeVersionAdvisory {
  status?: string;
  latestVersion?: string | null;
  canUpdate?: boolean;
}

interface NativeCompatibilityAdvisory {
  latestVersionStatus?: string;
  message?: string | null;
}

interface NativeUpdateState {
  status?: string;
  message?: string | null;
}

interface NativeProviderWire {
  instanceId?: string;
  driver?: string;
  displayName?: string;
  enabled?: boolean;
  installed?: boolean;
  availability?: string;
  unavailableReason?: string;
  version?: string | null;
  message?: string;
  versionAdvisory?: NativeVersionAdvisory;
  compatibilityAdvisory?: NativeCompatibilityAdvisory;
  updateState?: NativeUpdateState;
}

interface NativeProviderList {
  providers?: NativeProviderWire[];
}

interface NativeUpdatePolicy {
  mode?: string;
}

interface NativePolicyLimits {
  updates?: NativeUpdatePolicy;
}

interface NativeManagedPolicy {
  organization?: string;
  limits?: NativePolicyLimits;
}

interface NativeMaintenanceCapabilities {
  serverSelfUpdate?: string;
  desktopAppUpdate?: boolean;
}

interface NativeMaintenanceEnvironment {
  serverVersion?: string;
  capabilities?: NativeMaintenanceCapabilities;
}

interface NativeMaintenanceConfig {
  environment?: NativeMaintenanceEnvironment;
  managedPolicy?: NativeManagedPolicy;
}

interface MaintenanceRpcRequest {
  _tag: string;
  id: string;
  tag: string;
  headers: string[][];
  payload: Object;
}

interface RefreshProvidersRequest {
  reloadSecrets: boolean;
  workspaceSnapshotsOnDemand: boolean;
}

interface UpdateProviderRequest {
  instanceId: string;
  provider: string;
}

interface ReleaseEntry {
  tag_name?: string;
  draft?: boolean;
}

type ReleaseChannel = 'stable' | 'nightly' | 'preview';

const RELEASES_PAGE = 'https://github.com/pingdotgg/t3code/releases';
const RELEASES_INDEX = 'https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100&page=';
const RELEASE_TIMEOUT_MS = 20000;
const VERSION_PATTERN = /^v?(\d+\.\d+\.\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/;

function grants(permissions: string[] | undefined, scope: string, legacyOperate: boolean): boolean {
  return permissions?.includes(scope) === true ||
    (legacyOperate && permissions?.includes('orchestration:operate') === true);
}

export function readMaintenanceProviders(value?: Object, permissions?: string[],
  legacyOperate: boolean = false): EnvironmentMaintenanceProvider[] {
  const rows = (value as NativeProviderList | undefined)?.providers;
  if (!rows || !Array.isArray(rows)) throw new Error('环境未返回有效的提供商状态。');
  const canManage = grants(permissions, 'providers:manage', legacyOperate);
  const providers: EnvironmentMaintenanceProvider[] = [];
  for (const provider of rows) {
    const instanceId = provider?.instanceId;
    const driver = provider?.driver;
    if (!provider || provider.enabled !== true || !instanceId || !validProviderInstanceId(instanceId) ||
      !driver || !validProviderInstanceId(driver)) continue;
    const latest = provider.versionAdvisory?.latestVersion;
    const compatibility = provider.compatibilityAdvisory?.latestVersionStatus;
    const status = provider.updateState?.status;
    const installed = provider.installed === true;
    const canUpdate = canManage && installed && provider.availability !== 'unavailable' &&
      provider.versionAdvisory?.status === 'behind_latest' && provider.versionAdvisory.canUpdate === true &&
      typeof latest === 'string' && !!latest &&
      compatibility !== 'broken' && compatibility !== 'unsupported' && status !== 'queued' && status !== 'running';
    const detail = provider.updateState?.message ?? provider.compatibilityAdvisory?.message ??
      provider.unavailableReason ?? provider.message;
    providers.push({
      instanceId, driver, label: provider.displayName ?? driver, version: installed ? provider.version ?? '版本未知' : '未安装',
      latestVersion: latest ?? undefined, canUpdate, status, detail,
    });
  }
  return providers;
}

export function readEnvironmentMaintenance(value?: Object, permissions?: string[],
  legacyOperate: boolean = false): EnvironmentMaintenanceSnapshot {
  const config = value as NativeMaintenanceConfig | undefined;
  const version = config?.environment?.serverVersion;
  if (typeof version !== 'string' || !version.trim()) throw new Error('环境未返回有效的 T3 Code 版本。');
  const capabilities = config?.environment?.capabilities;
  const method = capabilities?.serverSelfUpdate;
  const canSelfUpdate = method === 'boot-service' || method === 'respawn' ||
    (method === 'desktop-managed' && capabilities?.desktopAppUpdate === true);
  const organization = config?.managedPolicy?.organization;
  const updateDenial = config?.managedPolicy?.limits?.updates?.mode === 'off'
    ? (organization ?? '组织') + '管理 T3 Code 更新，已停用此环境的更新检查。'
    : undefined;
  return {
    version, organization, updateDenial,
    canCheck: !updateDenial && grants(permissions, 'environment:maintain', legacyOperate),
    canRefresh: permissions?.includes('orchestration:read') === true,
    providers: readMaintenanceProviders(value, permissions, legacyOperate),
    serverUpdateCapability: canSelfUpdate ? method : undefined,
  };
}

export function refreshEnvironmentProvidersRequest(): MaintenanceRpcRequest {
  const payload: RefreshProvidersRequest = { reloadSecrets: true, workspaceSnapshotsOnDemand: true };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.refreshProviders', payload, headers: [] };
}

export function updateEnvironmentProviderRequest(provider: EnvironmentMaintenanceProvider): MaintenanceRpcRequest {
  if (!provider.canUpdate || !validProviderInstanceId(provider.instanceId) || !validProviderInstanceId(provider.driver)) {
    throw new Error('当前无法更新此提供商。');
  }
  const payload: UpdateProviderRequest = { instanceId: provider.instanceId, provider: provider.driver };
  return { _tag: 'Request', id: REQUEST_ID, tag: 'server.updateProvider', payload, headers: [] };
}

function releaseChannel(version: string): ReleaseChannel {
  const match = /^[^-+]+-(nightly|preview)\.\d{8}\.\d+$/.exec(version);
  return match?.[1] === 'nightly' ? 'nightly' : match?.[1] === 'preview' ? 'preview' : 'stable';
}

function compareIdentifiers(left: string, right: string): number {
  if (left === right) return 0;
  const leftNumeric = /^\d+$/.test(left);
  const rightNumeric = /^\d+$/.test(right);
  if (leftNumeric && rightNumeric) {
    const leftDigits = left.replace(/^0+(?=\d)/, '');
    const rightDigits = right.replace(/^0+(?=\d)/, '');
    if (leftDigits === rightDigits) return 0;
    return leftDigits.length - rightDigits.length || (leftDigits < rightDigits ? -1 : 1);
  }
  if (leftNumeric !== rightNumeric) return leftNumeric ? -1 : 1;
  return left < right ? -1 : 1;
}

function compareVersions(left: RegExpExecArray, right: RegExpExecArray): number {
  const leftCore = left[1].split('.');
  const rightCore = right[1].split('.');
  for (let index = 0; index < leftCore.length; index++) {
    const comparison = compareIdentifiers(leftCore[index], rightCore[index]);
    if (comparison !== 0) return comparison;
  }
  if (!left[2] || !right[2]) return Number(Boolean(right[2])) - Number(Boolean(left[2]));
  const leftParts = left[2].split('.');
  const rightParts = right[2].split('.');
  for (let index = 0; index < Math.min(leftParts.length, rightParts.length); index++) {
    const comparison = compareIdentifiers(leftParts[index], rightParts[index]);
    if (comparison !== 0) return comparison;
  }
  return leftParts.length - rightParts.length;
}

function releaseVersion(release: ReleaseEntry | undefined, channel: ReleaseChannel): string | undefined {
  const tag = release?.tag_name;
  if (release?.draft === true || typeof tag !== 'string' || !tag.startsWith('v') || !VERSION_PATTERN.test(tag)) {
    return undefined;
  }
  const version = tag.slice(1);
  return releaseChannel(version) === channel ? version : undefined;
}

async function readReleaseFeed(address: string, accept: string, deadline: number): Promise<string> {
  const timeout = deadline - Date.now();
  if (timeout <= 0) throw new Error('检查更新超时，请重试。');
  const request = http.createHttp();
  try {
    const headers: Record<string, string> = { 'Accept': accept };
    const response = await request.request(address, {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout,
      usingCache: false,
    });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error('无法检查 T3 Code 版本（HTTP ' + response.responseCode + '）。');
    }
    if (typeof response.result !== 'string') throw new Error('版本服务返回了无法读取的数据。');
    return response.result;
  } finally {
    request.destroy();
  }
}

export async function checkEnvironmentRelease(version: string): Promise<string | null> {
  const current = VERSION_PATTERN.exec(version);
  if (!current) throw new Error('当前 T3 Code 版本格式无效。');
  const channel = releaseChannel(version);
  const deadline = Date.now() + RELEASE_TIMEOUT_MS;
  let latest: string | undefined;
  if (channel === 'stable') {
    const text = await readReleaseFeed(RELEASES_PAGE + '/latest', 'application/json', deadline);
    const release = JSON.parse(text) as ReleaseEntry;
    if (typeof release?.tag_name !== 'string') throw new Error('版本服务返回了无效的发布信息。');
    latest = releaseVersion(release, channel);
  } else {
    const text = await readReleaseFeed(RELEASES_PAGE + '.atom', 'application/atom+xml', deadline);
    const tags = /<id>tag:github\.com,2008:Repository\/\d+\/([^<]+)<\/id>/g;
    let match = tags.exec(text);
    while (match && latest === undefined) {
      const entry: ReleaseEntry = { tag_name: match[1] };
      latest = releaseVersion(entry, channel);
      match = tags.exec(text);
    }
  }
  for (let page = 1; latest === undefined; page++) {
    const text = await readReleaseFeed(RELEASES_INDEX + page, 'application/vnd.github+json', deadline);
    const releases = JSON.parse(text) as ReleaseEntry[];
    if (!Array.isArray(releases)) throw new Error('版本服务返回了无效的发布列表。');
    for (const release of releases) {
      latest = releaseVersion(release, channel);
      if (latest !== undefined) break;
    }
    if (releases.length < 100) break;
  }
  if (latest === undefined) throw new Error('找不到当前渠道的 T3 Code 版本。');
  const parsed = VERSION_PATTERN.exec(latest);
  return parsed && compareVersions(parsed, current) > 0 ? latest : null;
}
