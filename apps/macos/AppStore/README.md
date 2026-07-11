# Mac App Store release checklist

App Store and TestFlight installs contain an App Store receipt, which enables the free/Pro entitlement checks. Normal source and GitHub builds contain no App Store receipt and continue to include Pro features. Local StoreKit testing enables commerce mode with the `TODAYMD_STOREKIT_TESTING=1` environment variable.

## App Store Connect

1. Create the macOS app with bundle ID `com.today-md.app`.
2. Accept the Paid Apps Agreement and complete banking and tax details.
3. Create a **Non-Consumable** In-App Purchase:
   - Reference name: `today-md Pro Lifetime`
   - Product ID: `com.today-md.app.pro.lifetime`
   - Price: `USD 19.99` with Apple's automatic storefront conversion
   - Family Sharing: enabled
4. Use the English localization from `today-md.storekit`.
5. Add the first IAP to the app version submission. Include a screenshot of the Pro purchase screen in the IAP review information.
6. Set the app itself to **Free**. The lifetime unlock is the paid product.

The App Store build detects its receipt and applies the free allowance of one list and five total tasks. Direct source/GitHub builds have Pro access. Existing over-limit data is preserved, but new lists/tasks and over-limit imports require Pro.

Product IDs are permanent. If the App Store Connect product ID changes, update `TodayMdPurchaseManager.lifetimeProductID` and this StoreKit configuration before shipping.

## Account-specific Xcode setup

1. Select the `today-md` target, then Signing & Capabilities.
2. Choose the Apple Developer team that owns `com.today-md.app`. The team is intentionally not committed so contributors can build the open-source project without your signing account.
3. Confirm the App Sandbox capability contains:
   - User Selected File: Read/Write
   - Calendars: Read/Write
4. Edit the Run action for the `today-md` scheme, select `AppStore/today-md.storekit` under StoreKit Configuration, and add `TODAYMD_STOREKIT_TESTING=1` to the scheme environment.
5. Test the first and fifth task, the second list, the sixth task from every quick-add surface, an over-limit import, purchase, cancellation, pending approval, restore with no purchase, restore with a purchase, and revocation.
6. Remove the local StoreKit configuration and test environment variable before a TestFlight sanity check.
7. Choose Product → Archive using the Release configuration.
8. In Organizer, run Validate App before Upload.

Do not notarize the Mac App Store archive separately. App Store distribution and direct-download Developer ID notarization are different workflows.

## App information

- Name: `today-md – Markdown Planner`
- Subtitle: `Local tasks. Markdown files.`
- Primary category: Productivity
- Support URL: `https://github.com/arthurliebhardt/today-md/issues`
- Privacy policy URL: `https://github.com/arthurliebhardt/today-md/blob/main/PRIVACY.md`
- App privacy: `No, we do not collect data from this app`, provided no analytics or remote service is added before submission.
- Copyright: `© 2026 Arthur Liebhardt`

Use the text under `metadata/en-US` for the first listing, then review it directly in App Store Connect before submission.

Capture the required 16:10 product images using `screenshots/README.md`. The existing repository screenshot has a different aspect ratio and should not be uploaded as-is.

## Review notes

Paste `review-notes.md` into App Review Information. The reviewer can exercise the core app without purchasing and can use Apple's review environment to test the lifetime product.

Before uploading, export a backup from the current GitHub build and verify importing it into a StoreKit-test build. This is the safest migration path because App Store and direct-distribution signatures can produce different container access behavior even when the bundle ID matches.
