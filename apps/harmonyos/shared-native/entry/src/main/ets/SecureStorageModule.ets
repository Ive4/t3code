import { relationalStore } from '@kit.ArkData';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class SecureStorageModule extends UITurboModule {
  private database: Promise<relationalStore.RdbStore> | undefined;

  private open(): Promise<relationalStore.RdbStore> {
    if (this.database === undefined) {
      this.database = this.initialize().catch((error: Error) => {
        this.database = undefined;
        throw error;
      });
    }
    return this.database;
  }

  private async initialize(): Promise<relationalStore.RdbStore> {
    const database = await relationalStore.getRdbStore(this.ctx.uiAbilityContext, {
      name: 'secure-storage.db',
      securityLevel: relationalStore.SecurityLevel.S3,
      encrypt: true,
    });
    await database.executeSql(
      'CREATE TABLE IF NOT EXISTS secrets (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
    );
    return database;
  }

  public async getItem(key: string): Promise<string | null> {
    const database = await this.open();
    const result = await database.querySql('SELECT value FROM secrets WHERE key = ?', [key]);
    try {
      return result.goToFirstRow() ? result.getString(0) : null;
    } finally {
      result.close();
    }
  }

  public async setItem(key: string, value: string): Promise<void> {
    const database = await this.open();
    await database.insert('secrets', { key, value }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  public async deleteItem(key: string): Promise<void> {
    const database = await this.open();
    await database.executeSql('DELETE FROM secrets WHERE key = ?', [key]);
  }
}
