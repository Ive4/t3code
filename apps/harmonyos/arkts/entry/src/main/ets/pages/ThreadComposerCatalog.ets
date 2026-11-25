import { util } from '@kit.ArkTS';
import { composerCommandContextReference, composerEnvironmentMentionRecord, composerPullRequestMentionRecord,
  composerThreadMentionRecord, serializeComposerCommandModel, serializeComposerCommandPath,
} from '../client/ComposerCommandProtocol';
import type { ComposerCommandTrigger } from '../client/ComposerCommandProtocol';
import { matchComposerThreadTitles } from '../client/ComposerCatalogProtocol';
import type { NativeComposerScope } from '../client/ComposerCatalogProtocol';
import type { EnvironmentSummary } from '../client/EnvironmentStore';
import { modelCatalogVisibleModels } from '../client/ModelCatalogPreferences';
import type { NativeLinkedEnvironment } from '../client/LinkedEnvironmentProtocol';
import type { NativeThread, T3Client } from '../client/T3Client';
import type { ThreadComposerSuggestion } from './ThreadComposerSuggestions';

export async function readThreadComposerSuggestions(client: T3Client, scope: NativeComposerScope,
  instanceId: string, trigger: ComposerCommandTrigger, canPickModel: boolean, canCompact: boolean,
  threads: NativeThread[], environments: EnvironmentSummary[]): Promise<ThreadComposerSuggestion[]> {
  const query = trigger.query.trim().toLowerCase();
  if (trigger.kind === 'pull-request') {
    const rows = await client.searchComposerPullRequests(scope, trigger.query);
    return rows.map((row): ThreadComposerSuggestion => {
      const record = composerPullRequestMentionRecord(row, util.generateRandomUUID());
      return { id: `pr:${row.host}:${row.repository}:${row.number}`, kind: 'pull-request', label: '#' + row.number,
        description: `${row.isDraft ? '草稿' : row.state === 'open' ? '开放' : row.state === 'merged' ? '已合并' : '已关闭'} · ${row.title}`,
        replacement: composerCommandContextReference(record) + ' ', record };
    });
  }
  if (trigger.kind === 'path') {
    const linked: Promise<NativeLinkedEnvironment[]> = query ? client.readComposerLinkedEnvironments(scope)
      .then((snapshot): NativeLinkedEnvironment[] => snapshot.links.filter((link: NativeLinkedEnvironment) =>
        link.expiresAtMs > Date.now() && link.status !== 'expired')).catch((): NativeLinkedEnvironment[] => []) :
      Promise.resolve([]);
    const modelSettings = query && scope.projectId ? client.composerModelSettings(scope).catch(() => undefined) :
      Promise.resolve(undefined);
    const paths = client.searchComposerPaths(scope, trigger.query).catch(() => undefined);
    const links = await linked;
    const settings = await modelSettings;
    const files = await paths;
    if (client.currentEnvironment()?.key !== scope.environmentKey) return [];
    const linkedIds = new Set(links.map((link: NativeLinkedEnvironment): string => link.environmentId));
    const hosts = environments.filter((environment) => environment.enabled);
    const linkedKeys = hosts.filter((environment) => linkedIds.has(environment.environmentId))
      .map((environment) => environment.key);
    const items: ThreadComposerSuggestion[] = [];
    for (const thread of matchComposerThreadTitles(threads, query, scope.environmentKey, scope.threadId, linkedKeys)) {
      const environment = hosts.find((host) => host.key === thread.environmentKey);
      if (!environment?.environmentId) continue;
      const record = composerThreadMentionRecord(environment.environmentId, thread.id, thread.title);
      items.push({ id: `thread:${environment.key}:${thread.id}`, kind: 'thread', label: thread.title,
        description: thread.projectTitle, replacement: composerCommandContextReference(record) + ' ', record });
    }
    const activeId = client.currentEnvironment()?.environmentId;
    const aliases = hosts.map((host) => host.environmentId);
    for (const environment of hosts.concat(links.filter((link) => !aliases.includes(link.environmentId)).map((link): EnvironmentSummary =>
      ({ key: '', environmentId: link.environmentId, label: link.label, origin: '', enabled: true, managed: false })))) {
      if (!query || !environment.environmentId || environment.environmentId === activeId ||
        !environment.label.toLowerCase().includes(query)) continue;
      const record = composerEnvironmentMentionRecord(environment.environmentId, environment.label);
      items.push({ id: `environment:${environment.environmentId}`, kind: 'environment', label: environment.label,
        description: '主机', replacement: composerCommandContextReference(record) + ' ', record });
    }
    let modelCount = 0;
    for (const provider of settings?.providers ?? []) {
      const models = modelCatalogVisibleModels(provider.models, settings?.modelCatalog, provider.instanceId, false, false);
      for (const model of models) {
        if (modelCount >= 8 || !query || !`${model.name} ${model.slug} ${provider.displayName}`.toLowerCase().includes(query)) continue;
        modelCount++;
        items.push({ id: `model:${provider.instanceId}:${model.slug}`, kind: 'model', label: model.name,
          description: provider.displayName, replacement: serializeComposerCommandModel(provider.instanceId, model.slug) + ' ' });
      }
    }
    for (const file of files ?? []) {
      const separator = file.path.lastIndexOf('/');
      items.push({ id: `file:${file.path}`, kind: file.kind === 'directory' ? 'directory' : 'file',
        label: file.name || file.path.slice(separator + 1), description: separator > 0 ? file.path.slice(0, separator) : undefined,
        replacement: serializeComposerCommandPath(file.path) + ' ' });
    }
    if (items.length === 0 && !files) throw new Error('无法从当前环境搜索文件。');
    return items;
  }
  const items: ThreadComposerSuggestion[] = [];
  if (trigger.kind === 'slash-command' && canPickModel && 'model'.includes(query)) {
    items.push({ id: 'model-picker', kind: 'model-picker', label: '/model', description: '切换模型', replacement: '' });
  }
  if (!instanceId) return items;
  const catalog = await client.readComposerProviderCatalog(scope, instanceId).catch((error: Error) => {
    if (items.length > 0) return undefined;
    throw error;
  });
  if (!catalog) return items;
  const skillNames = new Set(catalog.skills.map((skill) => skill.name.toLowerCase()));
  if (trigger.kind === 'slash-command' && trigger.rangeStart === 0) {
    for (const command of catalog.slashCommands) {
      const name = command.name.toLowerCase();
      if (!name.includes(query) || skillNames.has(name) || name === 'clear' || name === 'model' ||
        (name === 'compact' && !canCompact) || (catalog.driver === 'codex' && name === 'feedback' && !scope.threadId)) continue;
      items.push({ id: `command:${name}`, kind: 'command', label: '/' + command.name,
        description: command.description, replacement: '/' + command.name + ' ' });
    }
  }
  const skillQuery = trigger.kind === 'slash-command' && query === 'skill' ? '' :
    trigger.kind === 'slash-command' && query.startsWith('skill:') ? query.slice(6) : query;
  for (const skill of catalog.skills) {
    const label = skill.displayName || skill.name;
    const description = skill.shortDescription || skill.description;
    if (!`${skill.name} ${label} ${description ?? ''}`.toLowerCase().includes(skillQuery)) continue;
    items.push({ id: `skill:${skill.name}`, kind: 'skill', label: trigger.kind === 'slash-command' ? 'skill:' + skill.name : label,
      description, replacement: '$' + skill.name + ' ' });
    if (items.length >= 20) break;
  }
  return items;
}
