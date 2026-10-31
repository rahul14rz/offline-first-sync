import { z } from "zod";

const logLevels = ["fatal", "error", "warn", "info", "debug", "trace"] as const;

export type LogLevel = (typeof logLevels)[number];

export type Config = {
  host: string;
  port: number;
  databaseUrl: string;
  logLevel: LogLevel;
};

const envSchema = z.object({
  HOST: z.string().min(1).default("0.0.0.0"),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  LOG_LEVEL: z.enum(logLevels).default("info"),
});

/** Parses process environment into typed config. Throws one error listing every invalid variable. */
export function loadConfig(env: Record<string, string | undefined>): Config {
  const result = envSchema.safeParse(env);
  if (!result.success) {
    const problems = result.error.issues.map(
      (issue) => `  ${issue.path.join(".")}: ${issue.message}`,
    );
    throw new Error(`Invalid environment configuration:\n${problems.join("\n")}`);
  }
  const { HOST, PORT, DATABASE_URL, LOG_LEVEL } = result.data;
  return { host: HOST, port: PORT, databaseUrl: DATABASE_URL, logLevel: LOG_LEVEL };
}
