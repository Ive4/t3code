export type UiLanguage = 'zh' | 'en';
export type UiLanguagePreference = 'system' | UiLanguage;

export function readUiLanguagePreference(value: string): UiLanguagePreference {
  return value === 'zh' || value === 'en' ? value : 'system';
}

export function resolveUiLanguage(preference: UiLanguagePreference, systemLanguage: string): UiLanguage {
  if (preference !== 'system') return preference;
  const tag = systemLanguage.toLowerCase().split(/[-_]/)[0];
  return tag === 'zh' ? 'zh' : 'en';
}

export function uiText(language: UiLanguage, chinese: string, english: string): string {
  return language === 'zh' ? chinese : english;
}
