import { ScrollReveal } from "./ScrollReveal";

const lanes = [
  {
    name: "Today",
    color: "bg-primary",
    desc: "What you're doing right now. A short, focused list that resets your attention each morning.",
  },
  {
    name: "This Week",
    color: "bg-secondary",
    desc: "Committed work for the week. Drag tasks into Today when you're ready to act on them.",
  },
  {
    name: "Backlog",
    color: "bg-neutral-accent",
    desc: "Everything else. Ideas, someday-tasks, and things that haven't earned a deadline yet.",
  },
];

export function Workflow() {
  return (
    <section id="workflow" className="py-24 md:py-32">
      <div className="max-w-5xl mx-auto px-6">
        <ScrollReveal>
          <p className="text-primary text-sm font-medium tracking-wide uppercase mb-3">Workflow</p>
          <h2 className="font-display text-3xl md:text-4xl tracking-[-0.02em] leading-[1.15] text-foreground max-w-lg mb-6">
            Three lanes. Zero noise.
          </h2>
          <p className="text-muted-foreground text-base leading-relaxed max-w-lg mb-16 text-pretty">
            Organize work across three time horizons. Drag tasks forward as priorities shift. No sprints, no points, no ceremony.
          </p>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-6">
          {lanes.map((lane, i) => (
            <ScrollReveal key={lane.name} delay={i * 0.1}>
              <div className="relative rounded-xl border border-border/60 bg-background p-6 shadow-sm hover:shadow-md transition-shadow duration-300">
                <div className={`w-full h-1 ${lane.color} rounded-full mb-5 opacity-80`} />
                <h3 className="text-foreground font-semibold text-base mb-2">{lane.name}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty">{lane.desc}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>

        <ScrollReveal delay={0.3}>
          <div className="mt-12 grid sm:grid-cols-3 gap-6 text-sm">
            {[
              ["Lists & sublists", "Group tasks by project, context, or area of focus."],
              ["Checklists", "Break tasks into subtasks with checkboxes that track completion."],
              ["Markdown notes", "Attach rich notes to any task — formatted in real Markdown."],
            ].map(([title, desc]) => (
              <div key={title} className="border-t border-border pt-4">
                <p className="text-foreground font-medium mb-1">{title}</p>
                <p className="text-muted-foreground text-pretty leading-relaxed">{desc}</p>
              </div>
            ))}
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
