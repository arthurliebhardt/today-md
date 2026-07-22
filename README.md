# today-md

Monorepo for the native today-md macOS app and its public landing page.

| Package | Path | Stack |
|---|---|---|
| `@today-md/macos` | `apps/macos` | Swift 6, SwiftUI, SQLite |
| `@today-md/landingpage` | `apps/landingpage` | React 18, Vite 5, Tailwind CSS |

Both source repositories were imported with their Git histories. Generated macOS
release archives and local build outputs were intentionally removed during the
history import; source, tests, documentation, App Store metadata, and screenshots
remain in the repository.

## Commands

Run these from the monorepo root:

```sh
pnpm install
pnpm dev:landingpage    # Vite at http://localhost:8080
pnpm dev:macos          # build and open the native macOS app
pnpm build              # build both apps through Turborepo
pnpm test               # run Swift and Vitest tests
pnpm lint               # lint the landing page
pnpm type-check         # type-check both apps
```

App-specific commands can also be run with a workspace filter, for example:

```sh
pnpm --filter @today-md/landingpage test:watch
pnpm --filter @today-md/macos test
```

## Deployment

The landing page Docker image must be built with the monorepo root as its context:

```sh
docker build -f apps/landingpage/Dockerfile .
```

The deployment workflow is path-filtered to the landing page and shared workspace
files. Before enabling it in a new GitHub repository, migrate the existing
`KUBECONFIG_BASE64` and `DISCORD_WEBHOOK` secrets and grant the repository access
to `ghcr.io/liebhardt-io/today-md-landingpage`.

The native app's detailed development and release instructions remain in
[`apps/macos/README.md`](apps/macos/README.md).
