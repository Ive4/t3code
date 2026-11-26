import type { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';

export const USAGE_WIDGET_NAME = 'SubscriptionUsage';

export interface UsageWidgetRow {
  label: string;
  remaining: number;
  expiresAt: number;
}

interface UsageWidgetSnapshot {
  title: string;
  empty: string;
  refresh: string;
  asOf: string;
  rows: UsageWidgetRow[];
}

interface UsageWidgetBinding {
  title: string;
  message: string;
  asOf: string;
  rows: UsageWidgetRow[];
}

export function saveUsageWidgetSnapshot(context: common.Context, payload: string): void {
  const path = context.filesDir + '/subscription-usage-widget.json';
  const temporary = path + '.tmp';
  const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, payload);
  } finally {
    fileIo.closeSync(file);
  }
  fileIo.renameSync(temporary, path);
}

export function usageWidgetBinding(context: common.Context, formId?: string): formBindingData.FormBindingData {
  let snapshot: UsageWidgetSnapshot;
  try {
    snapshot = JSON.parse(fileIo.readTextSync(context.filesDir + '/subscription-usage-widget.json')) as UsageWidgetSnapshot;
  } catch {
    return formBindingData.createFormBindingData();
  }

  const now = Date.now();
  const rows = snapshot.rows.filter((row: UsageWidgetRow) => row.expiresAt > now);
  if (formId && rows.length > 0) {
    const deadline = Math.min(...rows.map((row: UsageWidgetRow) => row.expiresAt));
    const minutes = Math.max(5, Math.ceil((deadline - now) / 60_000));
    void formProvider.setFormNextRefreshTime(formId, minutes).catch(() => {
      console.warn('[t3-usage-widget] Could not schedule quota expiration.');
    });
  }
  const binding: UsageWidgetBinding = {
    title: snapshot.title,
    message: snapshot.rows.length > 0 ? snapshot.refresh : snapshot.empty,
    asOf: rows.length > 0 ? snapshot.asOf : '',
    rows,
  };
  return formBindingData.createFormBindingData(JSON.stringify(binding));
}

export async function updateUsageWidget(context: common.Context, formId: string): Promise<void> {
  await formProvider.updateForm(formId, usageWidgetBinding(context, formId));
}
