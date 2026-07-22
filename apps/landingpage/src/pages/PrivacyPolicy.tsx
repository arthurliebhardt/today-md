import { useEffect } from "react";
import { Footer } from "@/components/landing/Footer";
import { Navbar } from "@/components/landing/Navbar";

const sectionClassName = "space-y-4";
const headingClassName = "text-xl font-bold tracking-[-0.02em] text-foreground md:text-2xl";
const paragraphClassName = "text-base leading-7 text-muted-foreground md:text-[17px] md:leading-8";

const PrivacyPolicy = () => {
  useEffect(() => {
    const previousTitle = document.title;
    document.title = "Privacy Policy — today-md";
    window.scrollTo(0, 0);

    return () => {
      document.title = previousTitle;
    };
  }, []);

  return (
    <div className="min-h-screen bg-background">
      <Navbar />

      <main className="px-6 pb-20 pt-32 md:pb-28 md:pt-40">
        <article className="mx-auto max-w-[760px]">
          <header className="border-b border-border pb-12 md:pb-16">
            <p className="mb-5 text-xs font-semibold uppercase tracking-[0.18em] text-primary">
              Legal
            </p>
            <h1 className="max-w-2xl text-[clamp(2.75rem,7vw,5.25rem)] font-black leading-[0.95] tracking-[-0.055em] text-foreground">
              Privacy Policy
            </h1>
            <p className="mt-5 text-lg font-semibold text-foreground">for today-md</p>

            <dl className="mt-10 grid gap-5 text-sm sm:grid-cols-2">
              <div>
                <dt className="font-semibold text-foreground">Effective date</dt>
                <dd className="mt-1 text-muted-foreground">July 12, 2026</dd>
              </div>
              <div>
                <dt className="font-semibold text-foreground">Last updated</dt>
                <dd className="mt-1 text-muted-foreground">July 12, 2026</dd>
              </div>
            </dl>
          </header>

          <div className="space-y-12 pt-12 md:space-y-16 md:pt-16">
            <p className={`${paragraphClassName} text-foreground`}>
              today-md is a local-first macOS application developed by Arthur Liebhardt
              ("today-md," "we," "us," or "our"). This Privacy Policy explains how
              information is handled when you use the today-md application.
            </p>

            <section className={sectionClassName} aria-labelledby="privacy-summary">
              <h2 id="privacy-summary" className={headingClassName}>1. Summary</h2>
              <p className={paragraphClassName}>
                today-md does not require an account and does not include advertising,
                tracking, telemetry, or third-party analytics SDKs. We do not collect,
                transmit, sell, rent, or share your tasks, notes, calendar information,
                or other personal data through the app.
              </p>
              <p className={paragraphClassName}>
                Your data stays on your Mac unless you choose to export it or place it in
                a folder managed by a third-party sync provider.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="local-storage">
              <h2 id="local-storage" className={headingClassName}>2. Information stored on your Mac</h2>
              <p className={paragraphClassName}>
                today-md stores the information you create in the app, including tasks,
                subtasks, lists, Markdown notes, settings, and feature configuration,
                locally on your Mac. The app uses a local SQLite database and may create
                local Markdown mirrors and backups.
              </p>
              <p className={paragraphClassName}>We do not have access to this information.</p>
            </section>

            <section className={sectionClassName} aria-labelledby="folder-sync">
              <h2 id="folder-sync" className={headingClassName}>3. Optional folder sync</h2>
              <p className={paragraphClassName}>
                If you enable folder sync, today-md reads and writes app data only in the
                folder you select. The app stores a security-scoped bookmark on your Mac
                so it can continue accessing that folder with your permission.
              </p>
              <p className={paragraphClassName}>
                If the selected folder is managed by iCloud Drive, OneDrive, Dropbox, or
                another provider, that provider may process or store the files under its
                own privacy policy and terms. We do not control those providers or receive
                a copy of your files.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="calendar-access">
              <h2 id="calendar-access" className={headingClassName}>4. Optional Calendar access</h2>
              <p className={paragraphClassName}>
                If you enable Calendar integration and grant permission, today-md uses
                Apple&apos;s EventKit framework to read calendar events, display availability,
                and create time blocks at your direction. Calendar data is processed on
                your Mac and is not sent to us.
              </p>
              <p className={paragraphClassName}>
                You can change or revoke Calendar access at any time in macOS System Settings.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="purchases">
              <h2 id="purchases" className={headingClassName}>5. Purchases</h2>
              <p className={paragraphClassName}>
                Purchases are processed by Apple through the Mac App Store and StoreKit.
                Apple may process information such as your Apple Account, payment details,
                purchase history, and region under{" "}
                <a
                  href="https://www.apple.com/legal/privacy/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-medium text-foreground underline decoration-primary/60 underline-offset-4 transition-colors hover:text-primary"
                >
                  Apple&apos;s Privacy Policy
                </a>
                .
              </p>
              <p className={paragraphClassName}>
                today-md receives product and transaction information needed to determine
                whether Pro features are unlocked. We do not receive your full payment-card
                or bank-account details.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="support-github">
              <h2 id="support-github" className={headingClassName}>6. Support and GitHub</h2>
              <p className={paragraphClassName}>
                If you contact us or open a support request on GitHub, you choose what
                information to provide. GitHub processes that information under its own
                privacy terms, and information posted in a public issue may be visible to
                others. Please do not include sensitive task, note, calendar, or payment
                information in a public issue.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="data-retention">
              <h2 id="data-retention" className={headingClassName}>7. Data retention and deletion</h2>
              <p className={paragraphClassName}>
                Because we do not receive your app data, we do not retain it on
                developer-operated servers.
              </p>
              <div className={paragraphClassName}>
                <p>You control local data and may:</p>
                <ul className="mt-4 list-disc space-y-2 pl-6 marker:text-primary">
                  <li>delete tasks, notes, and lists in today-md;</li>
                  <li>disable folder sync in Settings;</li>
                  <li>revoke Calendar permission in macOS System Settings;</li>
                  <li>delete exported backups or synced files using Finder; and</li>
                  <li>uninstall today-md and delete its app container or Application Support data.</li>
                </ul>
              </div>
              <p className={paragraphClassName}>
                Deleting local files does not necessarily delete copies already stored by
                a sync or backup provider. Consult that provider for its deletion and
                retention controls.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="security">
              <h2 id="security" className={headingClassName}>8. Security</h2>
              <p className={paragraphClassName}>
                today-md uses the macOS app sandbox for its Mac App Store distribution and
                requests access only to features and files needed for the functions you
                choose. No storage method is completely secure, so you are responsible for
                protecting access to your Mac, backups, and selected sync accounts.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="children">
              <h2 id="children" className={headingClassName}>9. Children&apos;s privacy</h2>
              <p className={paragraphClassName}>
                today-md is a general-purpose productivity app and is not directed to
                children. The app does not knowingly collect personal information from
                children or other users.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="privacy-rights">
              <h2 id="privacy-rights" className={headingClassName}>10. Your privacy rights</h2>
              <p className={paragraphClassName}>
                Depending on where you live, you may have rights concerning personal data
                held by a business. We generally cannot access, correct, export, or delete
                data stored only on your device because we do not possess it. You can use
                the controls described above to manage that data directly.
              </p>
              <p className={paragraphClassName}>
                For information voluntarily provided in a support request, contact us using
                the method below.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="policy-changes">
              <h2 id="policy-changes" className={headingClassName}>11. Changes to this policy</h2>
              <p className={paragraphClassName}>
                We may update this Privacy Policy if today-md&apos;s features, data practices,
                or legal obligations change. We will update the date at the top of this
                document and, when appropriate, provide notice through the app, its
                distribution page, or the project repository.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="contact">
              <h2 id="contact" className={headingClassName}>12. Contact</h2>
              <p className={paragraphClassName}>
                For privacy questions or requests, email us at{" "}
                <a
                  href="mailto:support@todaymd.app"
                  className="font-medium text-foreground underline decoration-primary/60 underline-offset-4 transition-colors hover:text-primary"
                >
                  support@todaymd.app
                </a>
                .
              </p>
            </section>
          </div>
        </article>
      </main>

      <Footer />
    </div>
  );
};

export default PrivacyPolicy;
