# App Review notes

today-md is a local-first macOS task planner. It does not require an account and does not operate a remote backend.

The free experience includes the task board, one list, up to five total tasks, Markdown notes, search, and backup export. Existing over-limit data remains readable, editable, deletable, and exportable. The non-consumable In-App Purchase `com.today-md.app.pro.lifetime` removes the task/list limits and unlocks Calendar Planner, Week View, user-selected folder sync, and external Markdown reconciliation permanently.

To find the purchase:

1. Open Settings from the toolbar or press Command-,.
2. Select today-md Pro.
3. Choose Unlock Forever.

Restore Purchase is directly below the purchase button.

Calendar access is requested only when the user opens the Pro calendar settings and chooses to connect Calendar. Folder access is requested only through an `NSOpenPanel` after the user chooses a sync folder. The selected folder bookmark is stored locally.

The app contains no advertising, analytics SDK, account system, or developer-operated network service. StoreKit communicates with the App Store for product and transaction information.
