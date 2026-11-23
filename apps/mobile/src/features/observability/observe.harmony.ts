export const crashReportingAvailable = false;

export function setCrashReportsEnabled(_enabled: boolean) {
  return Promise.resolve();
}

export function reportRenderError(error: unknown) {
  console.error(error);
}
