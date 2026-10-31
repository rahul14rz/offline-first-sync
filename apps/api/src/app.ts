import Fastify, { type FastifyInstance } from "fastify";
import type pg from "pg";
import type { LogLevel } from "./config.js";

export type AppDeps = {
  pool: pg.Pool;
  logLevel: LogLevel | "silent";
};

type HealthResponse =
  { status: "ok"; database: "ok" } | { status: "unavailable"; database: "unreachable" };

export function buildApp({ pool, logLevel }: AppDeps): FastifyInstance {
  const app = Fastify({ logger: { level: logLevel } });

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

  return app;
}
