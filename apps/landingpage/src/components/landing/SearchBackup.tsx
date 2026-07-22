import { ScrollReveal } from "./ScrollReveal";
import { Search, Archive, FolderSync } from "lucide-react";

const features = [
  {
    icon: Search,
    title: "Global search",
    text: "Find anything across task titles, notes, and subtasks. Instant, local, and always available — even offline.",
  },
  {
    icon: Archive,
    title: "Backups & exports",
    text: "Export your entire workspace as JSON. Export notes as Markdown files. Restore from backup at any time.",
  },
  {
    icon: FolderSync,
    title: "Optional folder sync",
    text: "Point today-md at an iCloud Drive, OneDrive, or Dropbox folder to sync across Macs. Conflict-aware and user-controlled.",
  },
];

export function SearchBackup() {
  return (
    <section className="py-28 md:py-36 bg-section-alt">
      <div className="max-w-[1120px] mx-auto px-6">
        <ScrollReveal>
          <div className="text-center max-w-2xl mx-auto mb-20">
            <p className="text-primary text-sm font-semibold tracking-wide uppercase mb-4">Reliability</p>
            <h2 className="text-foreground text-3xl md:text-5xl font-bold tracking-[-0.035em] leading-[1.1] text-balance">
              Search, backup, sync on your terms.
            </h2>
          </div>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-12 md:gap-16">
          {features.map((f, i) => (
            <ScrollReveal key={f.title} delay={i * 0.08}>
              <div className="text-center">
                <div className="w-12 h-12 rounded-2xl bg-card border border-border/50 flex items-center justify-center mb-5 mx-auto">
                  <f.icon className="w-5 h-5 text-foreground" strokeWidth={1.5} />
                </div>
                <h3 className="text-foreground font-semibold text-base mb-2">{f.title}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty max-w-xs mx-auto">{f.text}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
