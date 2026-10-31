import { describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";

const databaseUrl = "postgres://sync:sync@localhost:5432/sync";

describe("loadConfig", () => {
  it("applies defaults when only DATABASE_URL is set", () => {
    expect(loadConfig({ DATABASE_URL: databaseUrl })).toEqual({
      host: "0.0.0.0",
      port: 3000,
      databaseUrl,
      logLevel: "info",
    });
  });

  it("reads every variable from the environment", () => {
    expect(
      loadConfig({
        DATABASE_URL: databaseUrl,
        HOST: "127.0.0.1",
        PORT: "8080",
        LOG_LEVEL: "debug",
      }),
    ).toEqual({ host: "127.0.0.1", port: 8080, databaseUrl, logLevel: "debug" });
  });

  it("names every invalid variable in one error", () => {
    const load = () => loadConfig({ PORT: "abc", LOG_LEVEL: "loud" });
    expect(load).toThrow(/DATABASE_URL/);
    expect(load).toThrow(/PORT/);
    expect(load).toThrow(/LOG_LEVEL/);
  });

  it("rejects a DATABASE_URL that is not a Postgres URL", () => {
    expect(() => loadConfig({ DATABASE_URL: "mysql://localhost/db" })).toThrow(/DATABASE_URL/);
  });
});
