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
    <section className="py-24 md:py-32">
      <div className="max-w-5xl mx-auto px-6">
        <ScrollReveal>
          <p className="text-primary text-sm font-medium tracking-wide uppercase mb-3">Reliability</p>
          <h2 className="font-display text-3xl md:text-4xl tracking-[-0.02em] leading-[1.15] text-foreground max-w-md mb-16">
            Search, backup,<br />sync on your terms.
          </h2>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-8">
          {features.map((f, i) => (
            <ScrollReveal key={f.title} delay={i * 0.08}>
              <div>
                <div className="w-10 h-10 rounded-lg bg-section-alt flex items-center justify-center mb-4 border border-border/60">
                  <f.icon className="w-[18px] h-[18px] text-foreground" strokeWidth={1.5} />
                </div>
                <h3 className="text-foreground font-semibold text-[15px] mb-2">{f.title}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty">{f.text}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
