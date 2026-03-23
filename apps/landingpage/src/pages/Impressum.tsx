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
              <h2 className="text-foreground font-semibold text-lg mb-2">Angaben gemäß § 5 TMG</h2>
              <p>
                Arthur Liebhardt<br />
                [Straße und Hausnummer]<br />
                [PLZ Ort]<br />
                Deutschland
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Kontakt</h2>
              <p>
                E-Mail: [deine@email.de]<br />
                Telefon: [optional]
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Verantwortlich für den Inhalt nach § 55 Abs. 2 RStV</h2>
              <p>
                Arthur Liebhardt<br />
                [Straße und Hausnummer]<br />
                [PLZ Ort]
              </p>
            </section>

            <section>
              <h2 className="text-foreground font-semibold text-lg mb-2">Haftungsausschluss</h2>
              <h3 className="text-foreground font-medium mb-1">Haftung für Inhalte</h3>
              <p className="mb-3">
                Die Inhalte unserer Seiten wurden mit größter Sorgfalt erstellt. Für die Richtigkeit, Vollständigkeit und Aktualität der Inhalte können wir jedoch keine Gewähr übernehmen.
              </p>
              <h3 className="text-foreground font-medium mb-1">Haftung für Links</h3>
              <p>
                Unser Angebot enthält Links zu externen Webseiten Dritter, auf deren Inhalte wir keinen Einfluss haben. Für die Inhalte der verlinkten Seiten ist stets der jeweilige Anbieter oder Betreiber verantwortlich.
              </p>
            </section>
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}
