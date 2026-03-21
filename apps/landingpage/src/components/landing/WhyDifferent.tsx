import { ScrollReveal } from "./ScrollReveal";
import { Monitor, HardDrive, Feather } from "lucide-react";

const points = [
  {
    icon: Monitor,
    title: "Native to macOS",
    text: "Built for the Mac. No Electron wrapper, no browser tab. Feels like the rest of your desktop.",
  },
  {
    icon: HardDrive,
    title: "Local-first, always",
    text: "Tasks, subtasks, and notes live in a local SQLite store on your machine. No account required.",
  },
  {
    icon: Feather,
    title: "Calm by design",
    text: "No notifications, no team feeds, no activity graphs. Just a quiet space to decide what matters today.",
  },
];

export function WhyDifferent() {
  return (
    <section id="features" className="py-28 md:py-36 border-t border-border/40">
      <div className="max-w-[1120px] mx-auto px-6">
        <ScrollReveal>
          <div className="text-center max-w-2xl mx-auto mb-20">
            <p className="text-primary text-sm font-semibold tracking-wide uppercase mb-4">Why it feels different</p>
            <h2 className="text-foreground text-3xl md:text-5xl font-bold tracking-[-0.035em] leading-[1.1] text-balance">
              Your work stays on your machine.
            </h2>
          </div>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-12 md:gap-16">
          {points.map((p, i) => (
            <ScrollReveal key={p.title} delay={i * 0.08}>
              <div className="text-center">
                <div className="w-12 h-12 rounded-2xl bg-muted flex items-center justify-center mb-5 mx-auto">
                  <p.icon className="w-5 h-5 text-foreground" strokeWidth={1.5} />
                </div>
                <h3 className="text-foreground font-semibold text-base mb-2">{p.title}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty max-w-xs mx-auto">{p.text}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
