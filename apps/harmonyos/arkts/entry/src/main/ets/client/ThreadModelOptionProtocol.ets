import { validProviderInstanceId } from './T3Protocol';
import type { ThreadLaunchModel, ThreadLaunchSelection } from './ThreadLaunchProtocol';

export type ThreadModelOptionValue = string | boolean;

export interface ThreadModelOptionSelection {
  id: string;
  value: ThreadModelOptionValue;
}

export interface ThreadModelOptionChoice {
  id: string;
  label: string;
  description?: string;
  isDefault?: boolean;
}

export interface ThreadModelOptionDescriptor {
  id: string;
  label: string;
  description?: string;
  type: 'select' | 'boolean';
  currentValue?: ThreadModelOptionValue;
  options: ThreadModelOptionChoice[];
  promptInjectedValues?: string[];
  promptControlled?: boolean;
  promptLocked?: boolean;
  role?: string;
}

export interface ThreadModelCapabilities {
  optionDescriptors: ThreadModelOptionDescriptor[];
}

export interface ThreadModelOptionChange {
  selection: ThreadLaunchSelection;
  prompt: string;
}

interface ThreadModelSelectionWire {
  instanceId?: string;
  provider?: string;
  model?: string;
  options?: Object;
}

const ULTRATHINK = /\bultrathink\b/i;
const ULTRATHINK_PREFIX = /^Ultrathink:\s*/i;
const DEFAULT_VARIANT = 't3:default';

function nonBlank(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function cleanValue(value: Object | undefined): ThreadModelOptionValue | undefined {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string' && value.trim()) return value.trim();
  return undefined;
}

export function readThreadModelOptionSelections(value?: Object): ThreadModelOptionSelection[] | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const selections: ThreadModelOptionSelection[] = [];
  const seen = new Set<string>();
  const add = (rawId: string | undefined, rawValue: Object | undefined): void => {
    if (!nonBlank(rawId)) return;
    const id = rawId?.trim() ?? '';
    const selection = cleanValue(rawValue);
    if (selection !== undefined && !seen.has(id)) {
      seen.add(id);
      selections.push({ id, value: selection });
    }
  };
  if (Array.isArray(value)) {
    for (const option of value as ThreadModelOptionSelection[]) add(option?.id, option?.value);
  } else {
    const record = value as Record<string, Object>;
    for (const id of Object.keys(record)) add(id, record[id]);
  }
  return selections.length > 0 ? selections : undefined;
}

export function readThreadModelSelection(value?: Object): ThreadLaunchSelection | undefined {
  const selection = value as ThreadModelSelectionWire | undefined;
  const instanceId = selection?.instanceId ?? selection?.provider;
  const model = selection?.model;
  if (instanceId === undefined || !validProviderInstanceId(instanceId) || model === undefined || !nonBlank(model)) {
    return undefined;
  }
  const options = readThreadModelOptionSelections(selection?.options);
  return options ? { instanceId, model: model.trim(), options } : { instanceId, model: model.trim() };
}

export function readThreadModelCapabilities(value?: Object): ThreadModelCapabilities | undefined {
  const descriptors = (value as ThreadModelCapabilities | undefined)?.optionDescriptors;
  if (!Array.isArray(descriptors)) return undefined;
  const seen = new Set<string>();
  const normalized: ThreadModelOptionDescriptor[] = [];
  for (const descriptor of descriptors) {
    if (!nonBlank(descriptor?.id) || !nonBlank(descriptor?.label) || seen.has(descriptor.id) ||
      (descriptor.type !== 'select' && descriptor.type !== 'boolean')) continue;
    seen.add(descriptor.id);
    const options = descriptor.type === 'select' && Array.isArray(descriptor.options)
      ? descriptor.options.filter((option: ThreadModelOptionChoice) => nonBlank(option?.id) && nonBlank(option?.label))
      : [];
    normalized.push({ id: descriptor.id, label: descriptor.label, description: descriptor.description,
      type: descriptor.type, options, currentValue: cleanValue(descriptor.currentValue), role: descriptor.role,
      promptInjectedValues: Array.isArray(descriptor.promptInjectedValues) ? descriptor.promptInjectedValues : undefined });
  }
  return { optionDescriptors: normalized };
}

export function threadModelSelectionsEqual(left?: ThreadLaunchSelection, right?: ThreadLaunchSelection): boolean {
  if (left?.instanceId !== right?.instanceId || left?.model !== right?.model) return false;
  const held = left?.options ?? [];
  const next = right?.options ?? [];
  return held.length === next.length && held.every((entry: ThreadModelOptionSelection) =>
    next.some((option: ThreadModelOptionSelection) => option.id === entry.id && option.value === entry.value));
}

function migrateUltracode(options: ThreadModelOptionSelection[], descriptors: ThreadModelOptionDescriptor[]):
  ThreadModelOptionSelection[] {
  const effort = options.find((option: ThreadModelOptionSelection) => option.id === 'effort');
  if (effort?.value !== 'ultracode' || !descriptors.some((descriptor: ThreadModelOptionDescriptor) =>
    descriptor.type === 'boolean' && descriptor.id === 'ultracode')) return options;
  const migrated = options.map((option: ThreadModelOptionSelection): ThreadModelOptionSelection =>
    option.id === 'effort' ? { id: 'effort', value: 'xhigh' } : option);
  if (!migrated.some((option: ThreadModelOptionSelection) => option.id === 'ultracode')) {
    migrated.push({ id: 'ultracode', value: true });
  }
  return migrated;
}

function matchesDescriptor(descriptor: ThreadModelOptionDescriptor, value: ThreadModelOptionValue): boolean {
  if (descriptor.type === 'boolean') return typeof value === 'boolean';
  return typeof value === 'string' && !descriptor.promptInjectedValues?.includes(value) &&
    descriptor.options.some((choice: ThreadModelOptionChoice) => choice.id === value);
}

export function threadModelSelectionForTarget(instanceId: string, model: ThreadLaunchModel,
  previous?: ThreadLaunchSelection, remembered?: ThreadModelOptionSelection[]): ThreadLaunchSelection {
  if (previous?.instanceId === instanceId && previous.model === model.slug) return previous;
  const descriptors = model.capabilities?.optionDescriptors ?? [];
  const previousOptions = previous?.instanceId === instanceId ? previous.options : undefined;
  const options = migrateUltracode(remembered ?? previousOptions ?? [], descriptors)
    .filter((option: ThreadModelOptionSelection) => descriptors.some((descriptor: ThreadModelOptionDescriptor) =>
      descriptor.id === option.id && matchesDescriptor(descriptor, option.value)));
  return options.length > 0 ? { instanceId, model: model.slug, options } : { instanceId, model: model.slug };
}

export function withThreadModelOptionDefaults(model: ThreadLaunchModel | undefined,
  selection: ThreadLaunchSelection): ThreadLaunchSelection {
  if (!model?.capabilities?.optionDescriptors?.some((descriptor: ThreadModelOptionDescriptor) =>
    descriptor.id === 'fastMode' && descriptor.type === 'boolean') || selection.options?.some((option: ThreadModelOptionSelection) =>
      option.id === 'fastMode')) return selection;
  const fastOff: ThreadModelOptionSelection = { id: 'fastMode', value: false };
  return { instanceId: selection.instanceId, model: selection.model, options: (selection.options ?? []).concat(fastOff) };
}

function resolvedValue(descriptor: ThreadModelOptionDescriptor, value?: ThreadModelOptionValue):
  ThreadModelOptionValue | undefined {
  if (descriptor.type === 'boolean') {
    if (typeof value === 'boolean') return value;
    return typeof descriptor.currentValue === 'boolean' ? descriptor.currentValue : undefined;
  }
  const defaultChoice = descriptor.options.find((option: ThreadModelOptionChoice) => option.isDefault === true)?.id;
  if (typeof value === 'string') {
    if (descriptor.promptInjectedValues?.includes(value)) return defaultChoice;
    if (matchesDescriptor(descriptor, value)) return value;
  }
  const reported = descriptor.currentValue;
  return typeof reported === 'string' && matchesDescriptor(descriptor, reported) ? reported : defaultChoice;
}

export function threadModelOptionDescriptors(model: ThreadLaunchModel | undefined,
  selection?: ThreadLaunchSelection, prompt: string = ''): ThreadModelOptionDescriptor[] {
  const descriptors = model?.capabilities?.optionDescriptors ?? [];
  const options = migrateUltracode(selection ? withThreadModelOptionDefaults(model, selection).options ?? [] : [], descriptors);
  const primary = descriptors.find((descriptor: ThreadModelOptionDescriptor) => descriptor.type === 'select');
  return descriptors.map((descriptor: ThreadModelOptionDescriptor): ThreadModelOptionDescriptor => {
    const explicit = options.find((option: ThreadModelOptionSelection) => option.id === descriptor.id)?.value;
    let current = resolvedValue(descriptor, explicit);
    if (descriptor.id === 'variant' && selection && explicit === undefined) {
      current = descriptor.options.some((option: ThreadModelOptionChoice) => option.id === DEFAULT_VARIANT)
        ? DEFAULT_VARIANT : undefined;
    }
    const controlled = primary?.id === descriptor.id && !!descriptor.promptInjectedValues?.length && ULTRATHINK.test(prompt);
    return { id: descriptor.id, label: descriptor.label, description: descriptor.description, type: descriptor.type,
      currentValue: current, role: descriptor.role, promptInjectedValues: descriptor.promptInjectedValues,
      options: descriptor.options.filter((choice: ThreadModelOptionChoice) => !descriptor.promptInjectedValues?.includes(choice.id)),
      promptControlled: controlled, promptLocked: controlled && ULTRATHINK.test(prompt.replace(ULTRATHINK_PREFIX, '')) };
  });
}

export function changeThreadModelOption(model: ThreadLaunchModel | undefined, selection: ThreadLaunchSelection,
  id: string, value: ThreadModelOptionValue, prompt: string): ThreadModelOptionChange | undefined {
  const descriptors = threadModelOptionDescriptors(model, selection, prompt);
  const target = descriptors.find((descriptor: ThreadModelOptionDescriptor) => descriptor.id === id);
  if (!target || target.promptLocked || !matchesDescriptor(target, value)) return undefined;
  const options: ThreadModelOptionSelection[] = [];
  for (const descriptor of descriptors) {
    const next = descriptor.id === id ? value : descriptor.currentValue;
    if (next !== undefined && matchesDescriptor(descriptor, next)) options.push({ id: descriptor.id, value: next });
  }
  return {
    selection: { instanceId: selection.instanceId, model: selection.model, options },
    prompt: target.promptControlled ? prompt.replace(ULTRATHINK_PREFIX, '') : prompt,
  };
}
