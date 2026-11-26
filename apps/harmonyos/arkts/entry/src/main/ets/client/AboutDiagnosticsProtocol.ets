export interface DiagnosticCrashEntry {
  id: string;
  timestamp: string;
  summary: string;
  stackPreview: string;
}

export interface LicenseNoticeSummary {
  name: string;
  license: string;
  repository: string;
}

export function formatDiagnosticsReport(
  appVersion: string,
  environmentCount: number,
  crashes: DiagnosticCrashEntry[],
): string {
  const normalizedVersion =
    typeof appVersion === 'string' && appVersion.trim().length > 0
      ? appVersion.trim()
      : 'unknown';
  const normalizedEnvCount =
    Number.isFinite(environmentCount) && environmentCount > 0
      ? Math.floor(environmentCount)
      : 0;
  const crashList = Array.isArray(crashes) ? crashes : [];

  const lines: string[] = [
    'T3 Code HarmonyOS Diagnostics Report',
    `App Version: ${normalizedVersion}`,
    `Environments: ${normalizedEnvCount}`,
    `Recent Crashes (${crashList.length}):`,
  ];

  if (crashList.length === 0) {
    lines.push('None');
    return lines.join('\n');
  }

  for (let i = 0; i < crashList.length; i++) {
    const entry = crashList[i];
    const id = typeof entry.id === 'string' && entry.id.trim().length > 0 ? entry.id.trim() : `crash-${i + 1}`;
    const timestamp =
      typeof entry.timestamp === 'string' && entry.timestamp.trim().length > 0
        ? entry.timestamp.trim()
        : 'unknown-time';
    const summary =
      typeof entry.summary === 'string' && entry.summary.trim().length > 0
        ? entry.summary.trim()
        : 'No summary';
    lines.push(`- [${id}] ${timestamp}: ${summary}`);
    const stack = typeof entry.stackPreview === 'string' ? entry.stackPreview.trim() : '';
    if (stack.length > 0) {
      lines.push(`  Stack: ${stack}`);
    }
  }

  return lines.join('\n');
}

export function defaultOpenSourceLicenses(): LicenseNoticeSummary[] {
  return [
    {
      name: 'ArkUI',
      license: 'Apache-2.0',
      repository: 'https://gitee.com/openharmony/arkui_ace_engine',
    },
    {
      name: 'Ghostty VT',
      license: 'MIT',
      repository: 'https://github.com/ghostty-org/ghostty',
    },
    {
      name: 'Effect',
      license: 'MIT',
      repository: 'https://github.com/Effect-TS/effect',
    },
    {
      name: 'OpenHarmony ArkTS Runtime',
      license: 'Apache-2.0',
      repository: 'https://gitee.com/openharmony/arkcompiler_ets_runtime',
    },
  ];
}
