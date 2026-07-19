# today-md market strategy — research notes

Research date: 2026-07-18

## Decision frame

- Audience: product stakeholders.
- Delivery: portable HTML report backed by canonical `artifact.json`.
- Questions: who is most likely to adopt and pay now; which product changes most improve acquisition, activation, retention, or differentiation.
- Assumptions: macOS-only, small independent team, $19.99 lifetime Pro, no account or third-party behavioral analytics.

## Local product evidence

- Repository: https://github.com/arthurliebhardt/today-md
- Primary local sources inspected: `README.md`, `AppStore/README.md`, App Store metadata, purchase manager, calendar/sync services, task/store models, views, and tests.
- Product today: Today / This Week / Backlog board, custom lists, subtasks/checklists, rich Markdown task notes, FTS search, quick capture/menu bar, calendar time-blocking and week view, local SQLite plus Markdown mirror, JSON/Markdown portability, folder reconciliation, no account/telemetry.
- Commercial model: App Store free tier of one list and five total tasks; $19.99 lifetime Pro unlock; source and GitHub builds have full Pro.
- Trust issue: direct release is not notarized and documents Gatekeeper bypass steps.
- Key missing task fundamentals: true due dates, recurrence, reminders, task priority/tags, and natural-language dates.
- Verification: `swift test` passed 102 tests during the audit.

## Official competitor sources

- Apple Notes Markdown import/export: https://support.apple.com/guide/notes/import-export-and-print-notes-not201900c07/mac
- Apple Reminders tags and smart lists: https://support.apple.com/en-us/102223
- Apple Reminders dates/alerts: https://support.apple.com/en-ie/guide/reminders/remndc729e28/mac
- Apple Reminders subtasks: https://support.apple.com/en-euro/guide/reminders/remnfec66479/mac
- Things product: https://culturedcode.com/things/
- Things Mac pricing: https://culturedcode.com/things/support/articles/2803552/
- Things trial: https://culturedcode.com/things/support/articles/2803551/
- Things natural-language scheduling: https://culturedcode.com/things/support/articles/4438545/
- NotePlan product: https://noteplan.co/
- NotePlan pricing: https://noteplan.co/pricing
- Obsidian product: https://obsidian.md/
- Obsidian pricing: https://obsidian.md/pricing
- Plainlist: https://getplainlist.com/
- Loomline: https://loomline.paperheart.dev/
- Sunsama daily planning: https://www.sunsama.com/features/daily-planning-and-shutdown
- Sunsama pricing: https://sunsama.com/pricing
- Morgen product and pricing: https://www.morgen.so/ and https://www.morgen.so/pricing
- Akiflow product and pricing: https://akiflow.com/ and https://akiflow.com/pricing

## Official channel and platform sources

- App Store search: https://developer.apple.com/app-store/search/
- App information limits: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- App Tags: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-tags/
- Campaign links: https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links
- App Analytics: https://developer.apple.com/help/app-store-connect-analytics/
- Editorial nominations: https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/
- Apple Ads setup eligibility: https://ads.apple.com/app-store/help/get-started/0052-solve-setup-and-access-issues
- Product Page Optimization: https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization/
- Custom Product Pages: https://developer.apple.com/app-store/custom-product-pages/
- Show HN: https://news.ycombinator.com/showhn.html
- Product Hunt launch: https://www.producthunt.com/launch
- Homebrew acceptable casks: https://docs.brew.sh/Acceptable-Casks
- Homebrew tap trust: https://docs.brew.sh/Tap-Trust

## Required report structure map

1. Title.
2. Executive Summary.
3. Decision frame.
4. Key findings and evidence: beachhead, competition, positioning, App Store, channels, conversion, roadmap.
5. What not to build.
6. Next steps and 90-day sequence.
7. Measurement.
8. Further questions.
9. Caveats and assumptions.

## Evidence-design decisions

- Tables are used for segments, competitors, channel experiments, feature priorities, launch sequence, and learning rules because each task is an exact multi-attribute lookup or prioritization decision.
- All tables use full-width, spacious layout and an explicit default sort.
- One native bar chart compares current public sticker prices and visibly groups one-time licenses versus annual subscriptions. It supports the pricing decision while its adjacent narrative warns that the billing models are not total-cost equivalents.
- No opportunity-score, market-size, or feature-count chart is used. Those would turn qualitative evidence into invented precision.
- Public counts, prices, policies, and availability were checked as of the research date. Strategic thresholds are labeled as hypotheses rather than benchmarks.

## Packaging and verification

- The portable reader's sticky header uses `100vw`, which exceeded the headless browser's document width by eight pixels when a classic vertical scrollbar was present. Packaging adds `html,body{overflow-x:clip}` to contain that reader-chrome overflow; report tables retain their own horizontal scrolling.
- Canonical validation, packaging, source-dialog interaction, and responsive browser verification passed at 1440px and 390px.
- Verified artifact counts: 23 blocks, 1 chart, and 6 tables.

## Caveats

- Desk research and local inspection are not substitutes for user interviews or retention data.
- GitHub metrics undercount usage and do not indicate active users.
- The App Store listing was not found as a publicly indexed live page during research.
- Emerging competitors may change quickly or publish inconsistent roadmap information.
- Community rules and platform eligibility can change; re-check them immediately before launch.
