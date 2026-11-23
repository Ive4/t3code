import { relationalStore } from '@kit.ArkData';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class ConnectionStoreModule extends UITurboModule {
  private database: relationalStore.RdbStore | undefined;

  private async open(): Promise<relationalStore.RdbStore> {
    if (this.database) {
      return this.database;
    }
    const database = await relationalStore.getRdbStore(this.ctx.uiAbilityContext, {
      name: 'connections.db',
      securityLevel: relationalStore.SecurityLevel.S3,
      encrypt: true,
    });
    await database.executeSql(
      'CREATE TABLE IF NOT EXISTS catalog (id INTEGER PRIMARY KEY, document TEXT NOT NULL)',
    );
    this.database = database;
    return database;
  }

  async readCatalog(): Promise<string | null> {
    const database = await this.open();
    const result = await database.querySql('SELECT document FROM catalog WHERE id = 1');
    try {
      return result.goToFirstRow() ? result.getString(0) : null;
    } finally {
      result.close();
    }
  }

  async writeCatalog(document: string): Promise<void> {
    const database = await this.open();
    await database.insert('catalog', { id: 1, document }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }
}
