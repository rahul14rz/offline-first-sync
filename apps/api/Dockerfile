# Build context is the repository root (see compose.yaml).
FROM node:22-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY apps/api/package.json apps/api/
RUN pnpm install --frozen-lockfile --filter @offline-first-sync/api
COPY apps/api apps/api
RUN pnpm --filter @offline-first-sync/api build \
 && pnpm --filter @offline-first-sync/api deploy --prod --legacy /out

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /out/package.json ./
COPY --from=build /out/node_modules node_modules
COPY --from=build /repo/apps/api/dist dist
COPY --from=build /repo/apps/api/drizzle drizzle
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
