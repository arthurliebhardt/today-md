import { ScrollReveal } from "./ScrollReveal";
import { Monitor, LayoutGrid, FileText, Search, HardDrive, CheckSquare, Download, Zap, Github } from "lucide-react";

const features = [
  { icon: Monitor, label: "Native\nmacOS app" },
  { icon: LayoutGrid, label: "Three-lane\nplanning" },
  { icon: FileText, label: "Markdown\nnotes" },
  { icon: Search, label: "Global\nsearch" },
  { icon: HardDrive, label: "Local-first\nstorage" },
  { icon: CheckSquare, label: "Checklists &\nsubtasks" },
  { icon: Download, label: "Backup &\nexport" },
  { icon: Zap, label: "Blazing fast\n& private" },
  { icon: Github, label: "Open\nsource" },
];

export function FeatureGrid() {
  return (
    <section className="py-20 md:py-28">
      <div className="max-w-[720px] mx-auto px-6">
        <div className="grid grid-cols-3 gap-y-14 gap-x-8">
          {features.map((f, i) => (
            <ScrollReveal key={f.label} delay={i * 0.05}>
              <div className="flex flex-col items-center text-center">
                <f.icon className="w-8 h-8 text-foreground mb-3" strokeWidth={1.2} />
                <p className="text-foreground font-semibold text-sm leading-snug whitespace-pre-line">
                  {f.label}
                </p>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
