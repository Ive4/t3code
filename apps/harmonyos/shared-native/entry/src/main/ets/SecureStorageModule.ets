import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const ASSET_NOT_FOUND = 24000002;

function privateAsset(key: string): asset.AssetMap {
  const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  attributes.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(key));
  return attributes;
}

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

  public setDeviceOnlyItem(key: string, value: string): void {
    const attributes = privateAsset(key);
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.addSync(attributes);
  }

  public async getDeviceOnlyItem(key: string): Promise<string | null> {
    const attributes = privateAsset(key);
    attributes.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const records = await asset.query(attributes);
      const value = records[0]?.get(asset.Tag.SECRET);
      return value instanceof Uint8Array ? util.TextDecoder.create('utf-8').decodeToString(value) : null;
    } catch (error) {
      if (error.code === ASSET_NOT_FOUND) return null;
      throw new Error('Could not read the device-only value.');
    }
  }

  public async deleteDeviceOnlyItem(key: string): Promise<void> {
    try {
      await asset.remove(privateAsset(key));
    } catch (error) {
      if (error.code !== ASSET_NOT_FOUND) throw new Error('Could not remove the device-only value.');
    }
  }
}
