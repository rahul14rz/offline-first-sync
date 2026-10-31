import type { FastifyInstance } from "fastify";
import type { z } from "zod";
import type { Db } from "../db.js";
import { readChanges } from "./changeLog.js";
import { pullQuery, type PullResponse } from "./protocol.js";

type InvalidRequest = { error: "invalid_request"; issues: { path: string; message: string }[] };

export function registerSyncRoutes(app: FastifyInstance, db: Db): void {
  app.get("/sync/pull", async (request, reply): Promise<PullResponse | InvalidRequest> => {
    const query = pullQuery.safeParse(request.query);
    if (!query.success) {
      reply.code(400);
      return invalidRequest(query.error);
    }
    return readChanges(db, Number(query.data.cursor), query.data.limit);
  });
}

function invalidRequest(error: z.ZodError): InvalidRequest {
  return {
    error: "invalid_request",
    issues: error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
  };
}
