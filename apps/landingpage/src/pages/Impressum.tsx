import { Link } from "react-router-dom";
import { Navbar } from "@/components/landing/Navbar";
import { Footer } from "@/components/landing/Footer";

export default function Impressum() {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <Navbar />
      <main className="pt-28 pb-20">
        <div className="max-w-[720px] mx-auto px-6">
          <Link to="/" className="text-muted-foreground hover:text-foreground text-sm mb-8 inline-flex items-center gap-1 transition-colors">
            ← Zurück
          </Link>
          <h1 className="text-3xl font-bold mb-8">Impressum</h1>

          <div className="space-y-6 text-[15px] leading-relaxed text-muted-foreground">
            <section>
              <p>
                liebhardt.io UG (haftungsbeschränkt)<br />
                Nußbaumstr. 29<br />
                66121 Saarbrücken<br />
                Germany
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Commercial Register</h2>
              <p>
                Registered at the Local Court (Amtsgericht) Saarbrücken<br />
                Registration Number: HRB 106575
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">VAT ID</h2>
              <p>
                Value Added Tax Identification Number in accordance with §27 a VAT Act:<br />
                DE366044881
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Contact</h2>
              <p>
                Email: <a href="mailto:support@todaymd.app" className="text-foreground hover:text-primary transition-colors">support@todaymd.app</a>
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Represented by</h2>
              <p>Managing Director: Arthur Liebhardt</p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Responsible for content according to § 55 Abs. 2 RStV</h2>
              <p>
                Arthur Liebhardt<br />
                Nußbaumstr. 29<br />
                66121 Saarbrücken<br />
                Germany
              </p>
            </section>
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}
