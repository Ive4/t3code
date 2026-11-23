import { preferences } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class LocalizationModule extends UITurboModule {
  private store(): preferences.Preferences {
    return preferences.getPreferencesSync(this.ctx.uiAbilityContext, { name: 'gt-localization' });
  }

  public getNativeLocales(): string[] {
    const preferred = i18n.System.getPreferredLanguageList();
    const locale = i18n.System.getSystemLocale();
    return preferred.includes(locale) ? preferred : [...preferred, locale];
  }

  public nativeStoreGet(key: string): string | null {
    const value = this.store().getSync(key, '');
    return typeof value === 'string' && value.length > 0 ? value : null;
  }

  public nativeStoreSet(key: string, value: string): void {
    const store = this.store();
    store.putSync(key, value);
    void store.flush().catch(() => console.warn('Could not save translation preferences.'));
  }

  public multiply(a: number, b: number): number {
    return a * b;
  }
}
