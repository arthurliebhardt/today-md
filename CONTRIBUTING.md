# Contributing to today-md

Thanks for your interest in improving `today-md`.

## Development Setup

Requirements:

- macOS 14 or newer
- Swift 6.2 or newer
- Xcode with the macOS SDK for running the app bundle

Clone the repo and build from the command line:

```bash
swift build
swift run today-md
```

For the full macOS app experience, including the app icon and bundle behavior, run:

```bash
bash scripts/dev-run.sh
```

You can also open `today-md.xcodeproj` in Xcode and run the `today-md` target.

## Project Notes

- The app uses SwiftUI with `@Observable` models.
- Data is stored locally in SQLite.
- Search is backed by SQLite full-text search.
- Markdown notes are mirrored to Application Support during normal app use.

## Contribution Guidelines

- Keep changes focused and scoped to the problem being solved.
- Match the existing Swift and SwiftUI style in the repository.
- Prefer small, reviewable pull requests over large mixed changes.
- Update documentation when behavior, setup, or user-facing flows change.
- Avoid committing generated build artifacts unless the change is intentionally a release artifact update.

## Before Opening a Pull Request

- Build the project with `swift build`.
- Launch the app locally and sanity-check the affected workflow.
- If you changed import, export, search, or persistence behavior, test with real sample data.
- Include a concise summary of what changed and any manual verification steps in the pull request description.

## Bug Reports and Feature Requests

When opening an issue or pull request, it helps to include:

- Your macOS version
- Your Xcode and Swift version
- Clear reproduction steps
- Screenshots or screen recordings for UI issues
- Notes about expected behavior versus actual behavior
