import { TurboModuleRegistry } from "react-native";

const nativeSQLite = TurboModuleRegistry.getEnforcing("T3SQLite");
const databaseName = "t3code-client.db";
let references = 0;

function makeQueue() {
  let tail = Promise.resolve();
  return (operation) => {
    const result = tail.then(operation);
    tail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  };
}

const scheduleDatabase = makeQueue();

function splitStatements(sql) {
  if (typeof sql !== "string" || sql.includes("\0")) {
    throw new TypeError("Harmony SQLite expects an SQL string without NULs");
  }
  const statements = [];
  // Match quoted identifiers, literals, and comments before looking for delimiters.
  const tokens =
    /'(?:''|[^'])*'|"(?:""|[^"])*"|\x60(?:\x60\x60|[^\x60])*\x60|\[[^\]]*\]|--[^\r\n]*|\/\*[\s\S]*?(?:\*\/|$)|;/g;
  let end = 0;
  let statement = "";
  const appendStatement = () => {
    const sql = statement.trim();
    if (sql) statements.push(sql);
    statement = "";
  };
  for (const match of sql.matchAll(tokens)) {
    const token = match[0];
    statement += sql.slice(end, match.index);
    if (token === ";") {
      appendStatement();
    } else {
      statement += token.startsWith("--") || token.startsWith("/*") ? " " : token;
    }
    end = match.index + token.length;
  }
  statement += sql.slice(end);
  appendStatement();
  for (const statement of statements) {
    if (
      /^(?:CREATE\s+(?:(?:TEMP|TEMPORARY)\s+)?TRIGGER|BEGIN|COMMIT|END|ROLLBACK|SAVEPOINT|RELEASE)\b/i.test(
        statement,
      )
    ) {
      throw new Error("Harmony SQLite does not accept trigger or transaction SQL");
    }
  }
  return statements;
}

function oneStatement(sql) {
  const statements = splitStatements(sql);
  if (statements.length !== 1) {
    throw new Error("Harmony SQLite expects a single SQL statement");
  }
  return statements[0];
}

function positionalBindings(args) {
  const bindings = args.length === 1 && Array.isArray(args[0]) ? args[0] : args;
  return Array.from(bindings, (value) => {
    if (
      value === null ||
      typeof value === "string" ||
      typeof value === "boolean" ||
      Number.isFinite(value)
    ) {
      return value;
    }
    throw new TypeError("Harmony SQLite expects positional scalar bindings");
  });
}

function statementMethods(schedule, inTransaction) {
  const select = async (sql, args, firstOnly) => {
    const statement = oneStatement(sql);
    const bindings = positionalBindings(args);
    const { columns, rows } = await schedule(() =>
      nativeSQLite.query(statement, bindings, firstOnly, inTransaction),
    );
    return rows.map((row) => Object.fromEntries(columns.map((name, index) => [name, row[index]])));
  };

  return {
    async execAsync(sql) {
      const statements = splitStatements(sql);
      await schedule(async () => {
        for (const statement of statements) {
          await nativeSQLite.execute(statement, [], inTransaction);
        }
      });
    },
    async runAsync(sql, ...args) {
      const statement = oneStatement(sql);
      const bindings = positionalBindings(args);
      await schedule(() => nativeSQLite.execute(statement, bindings, inTransaction));
    },
    async getFirstAsync(sql, ...args) {
      const [row] = await select(sql, args, true);
      return row ?? null;
    },
    async getAllAsync(sql, ...args) {
      return select(sql, args, false);
    },
  };
}

export async function openDatabaseAsync(name, options, directory) {
  if (name !== databaseName || options !== undefined || directory !== undefined) {
    throw new Error("Harmony SQLite supports only the default T3 mobile database");
  }

  return scheduleDatabase(async () => {
    if (references === 0) await nativeSQLite.open(name);
    references++;
    let closed = false;

    const schedule = (operation) =>
      scheduleDatabase(() => {
        if (closed) throw new Error("Harmony SQLite database is closed");
        return operation();
      });

    return {
      ...statementMethods(schedule, false),
      async withExclusiveTransactionAsync(callback) {
        await schedule(async () => {
          if (typeof callback !== "function")
            throw new TypeError("Expected a SQLite transaction callback");
          await nativeSQLite.begin();
          const enqueueTransaction = makeQueue();
          let active = true;
          const scheduleTransaction = (operation) => {
            if (!active) return Promise.reject(new Error("Harmony SQLite transaction is closed"));
            return enqueueTransaction(operation);
          };
          try {
            await callback(statementMethods(scheduleTransaction, true));
            active = false;
            await enqueueTransaction(() => nativeSQLite.commit());
          } catch (error) {
            active = false;
            try {
              await enqueueTransaction(() => nativeSQLite.rollback());
            } catch (rollbackError) {
              throw new AggregateError(
                [error, rollbackError],
                "Harmony SQLite could not roll back the transaction",
                { cause: rollbackError },
              );
            }
            throw error;
          }
        });
      },
      async closeAsync() {
        await scheduleDatabase(async () => {
          if (closed) return;
          if (references === 1) await nativeSQLite.close();
          references--;
          closed = true;
        });
      },
    };
  });
}
