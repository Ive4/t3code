import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const DATABASE_NAME = 't3code-client.db';
const PAYLOAD_CHUNK_BYTES = 512 * 1024;

type SQLiteValue = string | number | boolean | null;
type Database = relationalStore.RdbStore | relationalStore.Transaction;

class SQLiteRows {
  columns: string[];
  rows: SQLiteValue[][] = [];

  constructor(columns: string[]) {
    this.columns = columns;
  }
}

function getScalar(value: relationalStore.ValueType): SQLiteValue {
  if (value === null) return null;

  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  throw new Error('Unsupported Harmony SQLite result value');
}

function readRows(result: relationalStore.ResultSet, firstOnly: boolean): SQLiteRows {
  try {
    const count = firstOnly ? Math.min(result.rowCount, 1) : result.rowCount;
    if (count < 0) {
      throw new Error('Harmony SQLite could not read the result rows');
    }
    const output = new SQLiteRows(result.columnNames);
    for (let rowIndex = 0; rowIndex < count; rowIndex++) {
      if (!result.goToNextRow()) {
        throw new Error('Harmony SQLite result ended early');
      }
      const row: SQLiteValue[] = [];
      for (let column = 0; column < output.columns.length; column++) {
        row.push(getScalar(result.getValue(column)));
      }
      output.rows.push(row);
    }
    return output;
  } finally {
    result.close();
  }
}

async function readPayloadRows(
  db: Database,
  sql: string,
  bindings: SQLiteValue[],
  firstOnly: boolean,
  hasTimestamp: boolean,
): Promise<SQLiteRows> {
  // ArkData cursors through API 22 cannot read a row larger than 2 MiB.
  const timestamp = hasTimestamp ? ', updatedAt' : '';
  const limit = firstOnly ? ' LIMIT 1' : '';
  const chunkSize = PAYLOAD_CHUNK_BYTES.toString();
  const chunkQuery =
    'WITH RECURSIVE payloads AS MATERIALIZED (' +
    '  SELECT ROW_NUMBER() OVER () AS row_number, CAST(payload AS BLOB) AS bytes' + timestamp +
    '  FROM (' + sql + ')' + limit +
    '), chunks(row_number, byte_offset, byte_length) AS (' +
    '  SELECT row_number, 1, LENGTH(bytes) FROM payloads' +
    '  UNION ALL' +
    '  SELECT row_number, byte_offset + ' + chunkSize + ', byte_length FROM chunks' +
    '  WHERE byte_offset + ' + chunkSize + ' <= byte_length' +
    ')' +
    ' SELECT chunks.row_number, byte_offset, byte_length, SUBSTR(bytes, byte_offset, ' + chunkSize + ')' +
    timestamp + ' FROM chunks JOIN payloads USING (row_number) ORDER BY chunks.row_number, byte_offset';
  const result = await db.querySql(chunkQuery, bindings);
  try {
    const count = result.rowCount;
    if (count < 0) {
      throw new Error('Harmony SQLite could not read the payload rows');
    }
    const output = new SQLiteRows(hasTimestamp ? ['payload', 'updatedAt'] : ['payload']);
    const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
    let payload = new Uint8Array(0);
    let received = 0;
    for (let index = 0; index < count; index++) {
      if (!result.goToNextRow()) {
        throw new Error('Harmony SQLite payload result ended early');
      }
      const rowNumber = result.getLong(0);
      const offset = result.getLong(1) - 1;
      const size = result.getLong(2);
      if (offset === 0) {
        if (received !== payload.length) {
          throw new Error('Harmony SQLite payload result is incomplete');
        }
        payload = new Uint8Array(size);
        received = 0;
      }
      if (offset !== received || payload.length !== size || rowNumber !== output.rows.length + 1) {
        throw new Error('Harmony SQLite payload bytes are out of order');
      }
      if (size > 0) {
        const chunk = result.getBlob(3);
        if (chunk.length !== Math.min(PAYLOAD_CHUNK_BYTES, size - offset)) {
          throw new Error('Harmony SQLite payload chunk has an unexpected length');
        }
        payload.set(chunk, offset);
        received += chunk.length;
      }
      if (received === size) {
        const row: SQLiteValue[] = [size === 0 ? '' : decoder.decodeToString(payload)];
        if (hasTimestamp) {
          row.push(getScalar(result.getValue(4)));
        }
        output.rows.push(row);
      }
    }
    if (received !== payload.length) {
      throw new Error('Harmony SQLite payload result is incomplete');
    }
    return output;
  } finally {
    result.close();
  }
}

export class SQLiteModule extends UITurboModule {
  private store: relationalStore.RdbStore | undefined;
  private transaction: relationalStore.Transaction | undefined;

  public async open(name: string): Promise<void> {
    if (name !== DATABASE_NAME || this.store !== undefined) {
      throw new Error('Invalid Harmony SQLite open');
    }
    this.store = await relationalStore.getRdbStore(this.ctx.uiAbilityContext, {
      name,
      securityLevel: relationalStore.SecurityLevel.S3,
      encrypt: true,
    });
  }

  public async close(): Promise<void> {
    await this.requireStore().close();
    this.transaction = undefined;
    this.store = undefined;
  }

  public async execute(sql: string, bindings: SQLiteValue[], inTransaction: boolean): Promise<void> {
    const db = this.getDatabase(inTransaction);
    if (/^PRAGMA\s+journal_mode\s*=\s*WAL$/i.test(sql)) {
      // ArkData configures its connection pool in WAL mode when opening the store.
      const mode = await db.execute('PRAGMA journal_mode', []);
      if (typeof mode !== 'string' || mode.toLowerCase() !== 'wal') {
        throw new Error('Harmony SQLite database is not in WAL mode');
      }
      return;
    }
    await db.execute(sql, bindings);
  }

  public async query(sql: string, bindings: SQLiteValue[], firstOnly: boolean, inTransaction: boolean): Promise<SQLiteRows> {
    const db = this.getDatabase(inTransaction);
    if (/^PRAGMA\s+user_version$/i.test(sql)) {
      const result = new SQLiteRows(['user_version']);
      const version = await db.execute(sql, bindings);
      if (typeof version !== 'number' || !Number.isInteger(version)) {
        throw new Error('Harmony SQLite returned an invalid user_version');
      }
      result.rows.push([version]);
      return result;
    }
    const payloadQuery = /^SELECT\s+payload(\s*,\s*updated_at\s+AS\s+updatedAt)?\s+FROM\s+client_(cache|preferences)\b/i;
    const payloadMatch = payloadQuery.exec(sql);
    if (payloadMatch !== null) {
      return readPayloadRows(db, sql, bindings, firstOnly, payloadMatch[1] !== undefined);
    }
    return readRows(await db.querySql(sql, bindings), firstOnly);
  }

  public async begin(): Promise<void> {
    if (this.transaction !== undefined) {
      throw new Error('Harmony SQLite transaction is already active');
    }
    this.transaction = await this.requireStore().createTransaction({
      transactionType: relationalStore.TransactionType.EXCLUSIVE,
    });
  }

  public async commit(): Promise<void> {
    await this.requireTransaction().commit();
    this.transaction = undefined;
  }

  public async rollback(): Promise<void> {
    await this.requireTransaction().rollback();
    this.transaction = undefined;
  }

  private requireStore(): relationalStore.RdbStore {
    const store = this.store;
    if (store === undefined) {
      throw new Error('Harmony SQLite database is closed');
    }
    return store;
  }

  private requireTransaction(): relationalStore.Transaction {
    const transaction = this.transaction;
    if (transaction === undefined) {
      throw new Error('Harmony SQLite transaction is closed');
    }
    return transaction;
  }

  private getDatabase(inTransaction: boolean): Database {
    if (inTransaction) {
      return this.requireTransaction();
    }
    if (this.transaction !== undefined) {
      throw new Error('Harmony SQLite transaction is still active');
    }
    return this.requireStore();
  }
}
