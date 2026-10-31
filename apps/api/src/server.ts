import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool, runMigrations } from "./db.js";

let config;
try {
  config = loadConfig(process.env);
} catch (err) {
  console.error((err as Error).message);
  process.exit(1);
}

const pool = createPool(config.databaseUrl);
const app = buildApp({ pool, logLevel: config.logLevel });
app.addHook("onClose", () => pool.end());

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    app.log.info({ signal }, "shutting down");
    void app.close();
  });
}

app.log.info("running database migrations");
await runMigrations(pool);
await app.listen({ host: config.host, port: config.port });
