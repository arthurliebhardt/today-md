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
    text: "Tasks, subtasks, and notes live in a local SQLite store on your machine. No account required. No server dependency.",
  },
  {
    icon: Feather,
    title: "Calm by design",
    text: "No notifications, no team feeds, no activity graphs. Just a quiet space to decide what matters today.",
  },
];

export function WhyDifferent() {
  return (
    <section id="features" className="py-24 md:py-32 bg-section-alt">
      <div className="max-w-5xl mx-auto px-6">
        <ScrollReveal>
          <p className="text-primary text-sm font-medium tracking-wide uppercase mb-3">Why it feels different</p>
          <h2 className="font-display text-3xl md:text-4xl tracking-[-0.02em] leading-[1.15] text-foreground max-w-md mb-16">
            Your work stays<br />on your machine.
          </h2>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-12 md:gap-8">
          {points.map((p, i) => (
            <ScrollReveal key={p.title} delay={i * 0.08}>
              <div className="group">
                <div className="w-10 h-10 rounded-lg bg-background flex items-center justify-center mb-4 shadow-sm border border-border/60">
                  <p.icon className="w-[18px] h-[18px] text-foreground" strokeWidth={1.5} />
                </div>
                <h3 className="text-foreground font-semibold text-[15px] mb-2">{p.title}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty">{p.text}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>
      </div>
    </section>
  );
}
