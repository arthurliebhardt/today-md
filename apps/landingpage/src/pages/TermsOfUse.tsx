import { useEffect } from "react";
import { Link } from "react-router-dom";
import { Footer } from "@/components/landing/Footer";
import { Navbar } from "@/components/landing/Navbar";

const sectionClassName = "space-y-4";
const headingClassName = "text-xl font-bold tracking-[-0.02em] text-foreground md:text-2xl";
const paragraphClassName = "text-base leading-7 text-muted-foreground md:text-[17px] md:leading-8";
const linkClassName = "font-medium text-foreground underline decoration-primary/60 underline-offset-4 transition-colors hover:text-primary";

const TermsOfUse = () => {
  useEffect(() => {
    const previousTitle = document.title;
    document.title = "Terms of Use — today-md";
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
              Terms of Use
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
              These Terms of Use ("Terms") govern your use of the today-md macOS
              application (the "App"), developed by Arthur Liebhardt ("today-md," "we,"
              "us," or "our"). By downloading, installing, or using the App, you agree to
              these Terms. If you do not agree, do not use the App.
            </p>

            <section className={sectionClassName} aria-labelledby="app-store-open-source">
              <h2 id="app-store-open-source" className={headingClassName}>1. App Store and open-source terms</h2>
              <p className={paragraphClassName}>
                If you obtain the App through the Mac App Store, your license is also
                subject to{" "}
                <a
                  href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={linkClassName}
                >
                  Apple&apos;s Standard Licensed Application End User License Agreement
                </a>{" "}
                and the applicable Apple Media Services terms. These Terms supplement,
                and do not replace or conflict with, those Apple terms.
              </p>
              <p className={paragraphClassName}>
                Source code and builds distributed under the project&apos;s open-source license
                remain subject to the{" "}
                <a
                  href="https://github.com/arthurliebhardt/today-md/blob/main/LICENSE"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={linkClassName}
                >
                  MIT License
                </a>
                . If these Terms conflict with rights granted under the MIT License for an
                open-source copy, the MIT License controls for that copy.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="eligibility">
              <h2 id="eligibility" className={headingClassName}>2. Eligibility</h2>
              <p className={paragraphClassName}>
                You must be legally capable of entering into these Terms. If you use the App
                for an organization, you represent that you have authority to accept these
                Terms on its behalf.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="license-permitted-use">
              <h2 id="license-permitted-use" className={headingClassName}>3. License and permitted use</h2>
              <p className={paragraphClassName}>
                Subject to these Terms and the applicable distribution license, you may
                install and use the App for lawful personal or business productivity purposes.
              </p>
              <div className={paragraphClassName}>
                <p>You may not:</p>
                <ul className="mt-4 list-disc space-y-2 pl-6 marker:text-primary">
                  <li>use the App in violation of applicable law or another person&apos;s rights;</li>
                  <li>interfere with the App&apos;s security, integrity, or operation;</li>
                  <li>bypass purchase, entitlement, or feature-access controls; or</li>
                  <li>redistribute an App Store build except as permitted by Apple.</li>
                </ul>
              </div>
              <p className={paragraphClassName}>
                Nothing in this section restricts rights that applicable law or an
                open-source license gives you.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="content-responsibilities">
              <h2 id="content-responsibilities" className={headingClassName}>4. Your content and responsibilities</h2>
              <p className={paragraphClassName}>
                You retain ownership of tasks, notes, calendar entries, backups, and other
                content you create or manage with the App ("Your Content"). We do not claim
                ownership of Your Content.
              </p>
              <div className={paragraphClassName}>
                <p>You are responsible for:</p>
                <ul className="mt-4 list-disc space-y-2 pl-6 marker:text-primary">
                  <li>ensuring that you have the right to create, import, edit, or share Your Content;</li>
                  <li>reviewing calendar events before the App creates or changes them;</li>
                  <li>maintaining suitable backups; and</li>
                  <li>protecting your Mac and any folder-sync accounts you choose to use.</li>
                </ul>
              </div>
              <p className={paragraphClassName}>
                today-md is not a hosted storage or backup service, and we do not keep a
                server-side copy from which we can restore lost data.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="free-pro-features">
              <h2 id="free-pro-features" className={headingClassName}>5. Free and Pro features</h2>
              <p className={paragraphClassName}>
                The App may offer free features and an optional today-md Pro unlock. The
                features, limits, and price shown in the App at the time of purchase apply
                to that transaction.
              </p>
              <p className={paragraphClassName}>
                today-md Pro is offered as a one-time, non-consumable in-app purchase, not a
                recurring subscription. A purchase grants access to the Pro features made
                available for that product, subject to these Terms, Apple&apos;s terms, platform
                compatibility, and the continued availability of the App.
              </p>
              <p className={paragraphClassName}>
                Apple processes App Store purchases, billing, purchase restoration, and
                refunds. Refund eligibility is determined by Apple and applicable law. You
                can request an eligible refund through{" "}
                <a
                  href="https://support.apple.com/118223"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={linkClassName}
                >
                  Apple&apos;s refund service
                </a>
                .
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="third-party-services">
              <h2 id="third-party-services" className={headingClassName}>6. Third-party services</h2>
              <p className={paragraphClassName}>
                The App can interact, at your direction, with services provided by others,
                including Apple Calendar, the Mac App Store, iCloud Drive, OneDrive,
                Dropbox, or another folder provider. Your use of those services is governed
                by their respective terms and privacy policies.
              </p>
              <p className={paragraphClassName}>
                We are not responsible for a third-party service&apos;s availability, security,
                data handling, changes, or actions. Disabling or losing access to a
                third-party service may limit related App features.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="updates-availability">
              <h2 id="updates-availability" className={headingClassName}>7. Updates and availability</h2>
              <p className={paragraphClassName}>
                We may add, change, suspend, or discontinue App features or release updates
                to maintain compatibility, security, or functionality. We do not guarantee
                that every feature will remain available indefinitely or that the App will
                work with every future version of macOS or every third-party service.
              </p>
              <p className={paragraphClassName}>
                You are responsible for installing available updates and maintaining a
                compatible system. Any mandatory rights or remedies you have under
                applicable consumer law remain unaffected.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="intellectual-property">
              <h2 id="intellectual-property" className={headingClassName}>8. Intellectual property</h2>
              <p className={paragraphClassName}>
                Except for Your Content and components offered under an open-source license,
                the App, its branding, and its original materials are owned by Arthur
                Liebhardt and protected by applicable intellectual-property laws. No rights
                are granted except those expressly provided by these Terms, Apple&apos;s
                applicable license, or the MIT License.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="warranty-disclaimer">
              <h2 id="warranty-disclaimer" className={headingClassName}>9. Disclaimer of warranties</h2>
              <p className={paragraphClassName}>
                To the fullest extent permitted by applicable law, the App is provided "as
                is" and "as available," without warranties of any kind, whether express,
                implied, or statutory. We do not warrant that the App will be uninterrupted,
                error-free, compatible with every system, or immune from data loss.
              </p>
              <p className={paragraphClassName}>
                This disclaimer does not exclude warranties, guarantees, or other rights
                that cannot lawfully be excluded, including mandatory consumer rights.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="liability-limitation">
              <h2 id="liability-limitation" className={headingClassName}>10. Limitation of liability</h2>
              <p className={paragraphClassName}>
                To the fullest extent permitted by applicable law, we are not liable for
                indirect, incidental, special, consequential, or punitive damages, or for
                loss of data, profits, revenue, business, or opportunities arising from your
                use of or inability to use the App.
              </p>
              <p className={paragraphClassName}>
                Where liability cannot be excluded, our liability is limited only to the
                extent permitted by applicable law. Nothing in these Terms limits liability
                for fraud, intentional misconduct, gross negligence, death or personal
                injury caused by negligence, or any other liability that cannot lawfully be
                limited.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="termination">
              <h2 id="termination" className={headingClassName}>11. Termination</h2>
              <p className={paragraphClassName}>
                You may stop using the App at any time. Your rights under these Terms end if
                you materially breach them. Upon termination, you must stop using App Store
                copies of the App, but provisions that by their nature should survive will
                remain in effect, including ownership, disclaimers, limitations of liability,
                and dispute provisions.
              </p>
              <p className={paragraphClassName}>
                Termination does not override rights granted for source code under the MIT
                License, provided you continue to comply with that license.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="governing-rules">
              <h2 id="governing-rules" className={headingClassName}>12. Governing rules and consumer rights</h2>
              <p className={paragraphClassName}>
                These Terms are governed by applicable law, without depriving you of
                mandatory protections provided by the law of your country or region. If you
                are a consumer, you may bring a claim in any forum available to you under
                applicable consumer law.
              </p>
              <p className={paragraphClassName}>
                Before starting formal proceedings, we encourage you to contact us so we can
                try to resolve the issue.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="terms-changes">
              <h2 id="terms-changes" className={headingClassName}>13. Changes to these Terms</h2>
              <p className={paragraphClassName}>
                We may update these Terms to reflect changes to the App, distribution
                arrangements, or legal requirements. We will update the date at the top and,
                when appropriate, provide notice through the app, its distribution page, or
                the project repository. Changes apply prospectively. If you do not agree to
                updated Terms, you must stop using the affected version of the App.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="severability-agreement">
              <h2 id="severability-agreement" className={headingClassName}>14. Severability and entire agreement</h2>
              <p className={paragraphClassName}>
                If any provision of these Terms is found unenforceable, the remaining
                provisions remain in effect, and the affected provision will apply to the
                greatest extent permitted by law.
              </p>
              <p className={paragraphClassName}>
                These Terms, the{" "}
                <Link to="/privacy" className={linkClassName}>Privacy Policy</Link>, and any
                applicable Apple or open-source license terms form the agreement governing
                your use of the App.
              </p>
            </section>

            <section className={sectionClassName} aria-labelledby="contact">
              <h2 id="contact" className={headingClassName}>15. Contact</h2>
              <p className={paragraphClassName}>
                For questions about these Terms or the App, email us at{" "}
                <a
                  href="mailto:support@todaymd.app"
                  className={linkClassName}
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

export default TermsOfUse;
