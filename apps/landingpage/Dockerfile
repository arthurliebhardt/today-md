# syntax=docker/dockerfile:1.7
# Build from the monorepo root: docker build -f apps/landingpage/Dockerfile .

FROM node:22-alpine AS builder
WORKDIR /repo

RUN corepack enable && corepack prepare pnpm@10.30.3 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/landingpage/package.json apps/landingpage/package.json
RUN --mount=type=cache,id=pnpm-store,target=/pnpm-store \
    pnpm config set store-dir /pnpm-store && \
    pnpm install --frozen-lockfile --filter @today-md/landingpage...

COPY apps/landingpage apps/landingpage
RUN pnpm --filter @today-md/landingpage build

FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN npm install -g serve@14.2.4

COPY --from=builder /repo/apps/landingpage/dist ./dist

EXPOSE 3000

CMD ["serve", "-s", "dist", "-l", "3000"]
