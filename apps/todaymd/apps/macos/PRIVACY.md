# Privacy Policy for today-md

**Effective date:** July 12, 2026

**Last updated:** October 19, 2026

today-md is a local-first macOS application developed by Arthur Liebhardt ("today-md," "we," "us," or "our"). This Privacy Policy explains how information is handled when you use the today-md application.

## 1. Summary

today-md does not require an account and does not include advertising, tracking, telemetry, or third-party analytics SDKs. We do not collect, transmit, sell, rent, or share your tasks, notes, or calendar information through the app. Optional license activation and update checks send the limited information described below.

Your tasks, notes, and calendar information stay on your Mac unless you choose to export them or place them in a folder managed by a third-party sync provider.

## 2. Information stored on your Mac

today-md stores the information you create in the app, including tasks, subtasks, lists, Markdown notes, settings, and feature configuration, locally on your Mac. The app uses a local SQLite database and may create local Markdown mirrors and backups.

We do not have access to this information.

## 3. Optional folder sync

If you enable folder sync, today-md reads and writes app data only in the folder you select. The app stores a security-scoped bookmark on your Mac so it can continue accessing that folder with your permission.

If the selected folder is managed by iCloud Drive, OneDrive, Dropbox, or another provider, that provider may process or store the files under its own privacy policy and terms. We do not control those providers or receive a copy of your files.

## 4. Optional Calendar access

If you enable Calendar integration and grant permission, today-md uses Apple's EventKit framework to read calendar events, display availability, and create time blocks at your direction. Calendar data is processed on your Mac and is not sent to us.

You can change or revoke Calendar access at any time in macOS System Settings.

## 5. Purchases

In-app purchases are processed by Apple through the Mac App Store and StoreKit. Apple may process information such as your Apple Account, payment details, purchase history, and region under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

today-md receives product and transaction information needed to determine whether Pro features are unlocked. We do not receive your full payment-card or bank-account details.

You can also unlock Pro with a license bought on toolstokeep.com. Entering a short key beginning with `ttk_` makes a one-time request to toolstokeep.com in either the direct-download or Mac App Store edition. The request sends your license key, the app identifier, and a SHA-256 hash derived from your Mac's hardware identifier. The server also receives network information such as your IP address. These details are used to validate the purchase, enforce its device limit, and check for refunds or revocation. The raw hardware identifier, tasks, notes, and calendar information are not sent.

After activation, today-md verifies and stores a signed license credential in the macOS Keychain. It includes the license identifier, purchase email address, app identifier, issue date, and device limit. The credential lets the app stay unlocked offline. Existing long keys beginning with `TTK1.` are signed credentials and can be verified offline directly.

The direct-download edition contacts toolstokeep.com when you enter a signed key and about once a week while the app is in use to check for refunded or revoked licenses. The Mac App Store edition performs no automatic license checks and does not contact toolstokeep.com when you enter an existing signed key. Removing a license in the app removes its local credential. Website purchase and activation records are described in the [toolstokeep privacy policy](https://toolstokeep.com/legal/privacy).

## 6. Support and GitHub

The GitHub download edition uses Sparkle to check for and download app updates from GitHub. Update requests include network information such as your IP address and the app version; tasks, notes, and calendar data are not included. Sparkle system profiling is disabled. You can turn off automatic checks in Settings and check manually instead. The Mac App Store edition receives app updates through Apple.

If you contact us or open a support request on GitHub, you choose what information to provide. GitHub processes that information under its own privacy terms, and information posted in a public issue may be visible to others. Please do not include sensitive task, note, calendar, or payment information in a public issue.

## 7. Data retention and deletion

Because we do not receive your tasks, notes, or calendar information, we do not retain that content on developer-operated servers. Optional license activation records are handled as described in the toolstokeep privacy policy linked above.

You control local data and may:

- delete tasks, notes, and lists in today-md;
- disable folder sync in Settings;
- revoke Calendar permission in macOS System Settings;
- delete exported backups or synced files using Finder; and
- uninstall today-md and delete its app container or Application Support data.

Deleting local files does not necessarily delete copies already stored by a sync or backup provider. Consult that provider for its deletion and retention controls.

## 8. Security

today-md uses the macOS app sandbox for its Mac App Store distribution and requests access only to features and files needed for the functions you choose. No storage method is completely secure, so you are responsible for protecting access to your Mac, backups, and selected sync accounts.

## 9. Children's privacy

today-md is a general-purpose productivity app and is not directed to children. The app does not knowingly collect personal information from children.

## 10. Your privacy rights

Depending on where you live, you may have rights concerning personal data held by a business. We generally cannot access, correct, export, or delete data stored only on your device because we do not possess it. You can use the controls described above to manage that data directly.

For license activation records or information voluntarily provided in a support request, contact us using the method below.

## 11. Changes to this policy

We may update this Privacy Policy if today-md's features, data practices, or legal obligations change. We will update the date at the top of this document and, when appropriate, provide notice through the app, its distribution page, or the project repository.

## 12. Contact

For privacy questions or requests, email [support@todaymd.app](mailto:support@todaymd.app). General questions can also be raised at [github.com/arthurliebhardt/today-md/issues](https://github.com/arthurliebhardt/today-md/issues), but do not post personal license or purchase details in public issues.
