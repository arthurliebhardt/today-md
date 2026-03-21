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
    <section id="workflow" className="py-28 md:py-36 bg-section-alt">
      <div className="max-w-[1120px] mx-auto px-6">
        <ScrollReveal>
          <div className="text-center max-w-2xl mx-auto mb-6">
            <p className="text-primary text-sm font-semibold tracking-wide uppercase mb-4">Workflow</p>
            <h2 className="text-foreground text-3xl md:text-5xl font-bold tracking-[-0.035em] leading-[1.1] text-balance">
              Three lanes. Zero noise.
            </h2>
          </div>
          <p className="text-muted-foreground text-base md:text-lg leading-relaxed max-w-lg mx-auto mb-20 text-center text-pretty">
            Organize work across three time horizons. Drag tasks forward as priorities shift. No sprints, no points, no ceremony.
          </p>
        </ScrollReveal>

        <div className="grid md:grid-cols-3 gap-6">
          {lanes.map((lane, i) => (
            <ScrollReveal key={lane.name} delay={i * 0.1}>
              <div className="rounded-2xl border border-border/50 bg-card p-8 hover:shadow-lg transition-shadow duration-300">
                <div className={`w-full h-1 ${lane.color} rounded-full mb-6 opacity-70`} />
                <h3 className="text-foreground font-semibold text-lg mb-2">{lane.name}</h3>
                <p className="text-muted-foreground text-sm leading-relaxed text-pretty">{lane.desc}</p>
              </div>
            </ScrollReveal>
          ))}
        </div>

        <ScrollReveal delay={0.3}>
          <div className="mt-16 grid sm:grid-cols-3 gap-8 text-sm">
            {[
              ["Lists & sublists", "Group tasks by project, context, or area of focus."],
              ["Checklists", "Break tasks into subtasks with checkboxes that track completion."],
              ["Markdown notes", "Attach rich notes to any task — formatted in real Markdown."],
            ].map(([title, desc]) => (
              <div key={title} className="border-t border-border/50 pt-5">
                <p className="text-foreground font-semibold mb-1">{title}</p>
                <p className="text-muted-foreground text-pretty leading-relaxed">{desc}</p>
              </div>
            ))}
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
