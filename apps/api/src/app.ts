import Fastify, { type FastifyInstance } from "fastify";
import type pg from "pg";
import type { LogLevel } from "./config.js";
import { createDb } from "./db.js";
import { registerSyncRoutes } from "./sync/routes.js";

export type AppDeps = {
  pool: pg.Pool;
  logLevel: LogLevel | "silent";
};

type HealthResponse =
  { status: "ok"; database: "ok" } | { status: "unavailable"; database: "unreachable" };

export function buildApp({ pool, logLevel }: AppDeps): FastifyInstance {
  const app = Fastify({ logger: { level: logLevel } });

  // node-postgres emits "error" when the server drops an idle pooled connection (restart,
  // failover). Without a listener Node treats it as uncaught and exits. The pool discards
  // the client and opens a new one on the next query, so logging is enough.
  pool.on("error", (err) => {
    app.log.warn({ err }, "idle database connection closed");
  });

  app.get("/health", async (request, reply): Promise<HealthResponse> => {
    try {
      await pool.query("select 1");
      return { status: "ok", database: "ok" };
    } catch (err) {
      request.log.warn({ err }, "health check: database query failed");
      reply.code(503);
      return { status: "unavailable", database: "unreachable" };
    }
  });

  registerSyncRoutes(app, createDb(pool));

  return app;
}
