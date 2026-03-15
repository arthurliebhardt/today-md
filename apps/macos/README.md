# todo

A macOS task manager built with SwiftUI and SwiftData. The app organizes work into lists and three planning lanes: Today, This Week, and Backlog.

![todo app screenshot](docs/image.png)

## Features

- Multiple task lists with custom names, icons, and colors
- Kanban-style planning lanes for `Today`, `This Week`, and `Backlog`
- Task detail view with subtasks and Markdown notes
- Drag-and-drop task movement and reordering
- Import and export of task data as JSON backups
- Seeded sample data on first launch for local testing

## Tech Stack

- Swift 5
- SwiftUI
- SwiftData
- AppKit integrations for file import/export panels

## Requirements

- macOS 14.0+
- Xcode 15+

## Getting Started

1. Open `todo.xcodeproj` in Xcode.
2. Select the `todo` target.
3. Build and run the app on macOS.

The app stores its local data with SwiftData and creates sample lists and tasks the first time it launches.

## Project Structure

- `todo/TodoApp.swift`: app entry point and SwiftData container setup
- `todo/ContentView.swift`: split-view shell, settings, import, and export flows
- `todo/Models`: SwiftData models for lists, tasks, notes, and subtasks
- `todo/Views`: board, sidebar, and task detail UI
- `todo/Helpers/TodoTransferService.swift`: JSON backup import/export

## Data Portability

Backups are exported as JSON files. Imported data can either be merged into the existing store or replace it completely.
