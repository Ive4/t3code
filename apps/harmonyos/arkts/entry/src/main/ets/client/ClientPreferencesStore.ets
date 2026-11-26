import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  ClientPreferencesSnapshot,
  defaultClientPreferences,
  parseClientPreferences,
  serializeClientPreferences,
} from './ClientPreferencesProtocol';

const PREFERENCES_STORE_NAME = 'arkts-client-preferences';
const PREFERENCES_KEY = 'client_preferences_v1';

export class ClientPreferencesStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private async store(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, { name: PREFERENCES_STORE_NAME });
  }

  async load(): Promise<ClientPreferencesSnapshot> {
    try {
      const prefsStore = await this.store();
      const raw = await prefsStore.get(PREFERENCES_KEY, '');
      return typeof raw === 'string' ? parseClientPreferences(raw) : defaultClientPreferences();
    } catch (_) {
      return defaultClientPreferences();
    }
  }

  async save(prefs: ClientPreferencesSnapshot): Promise<void> {
    const prefsStore = await this.store();
    await prefsStore.put(PREFERENCES_KEY, serializeClientPreferences(prefs));
    await prefsStore.flush();
  }
}
