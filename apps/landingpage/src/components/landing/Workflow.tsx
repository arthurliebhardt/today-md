import { ScrollReveal } from "./ScrollReveal";

const lanes = [
  {
    name: "Today",
    color: "bg-primary",
    desc: "What you're doing right now. A short, focused list that resets your attention each morning.",
    tasks: [
      { label: "Finalize API auth flow", done: true },
      { label: "Write migration script", done: false },
      { label: "Review pull request #47", done: false },
    ],
  },
  {
    name: "This Week",
    color: "bg-secondary",
    desc: "Committed work for the week. Drag tasks into Today when you're ready to act on them.",
    tasks: [
      { label: "Draft onboarding copy", done: false },
      { label: "Set up CI pipeline", done: false },
      { label: "Design export modal", done: true },
      { label: "Update dependencies", done: false },
    ],
  },
  {
    name: "Backlog",
    color: "bg-neutral-accent",
    desc: "Everything else. Ideas, someday-tasks, and things that haven't earned a deadline yet.",
    tasks: [
      { label: "Explore CalDAV sync", done: false },
      { label: "Keyboard shortcut editor", done: false },
      { label: "Dark mode support", done: false },
    ],
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

        <div className="grid md:grid-cols-3 gap-6 items-stretch">
          {lanes.map((lane, i) => (
            <ScrollReveal key={lane.name} delay={i * 0.1} className="h-full">
              <div className="rounded-2xl border border-border/50 bg-card p-8 hover:shadow-lg transition-shadow duration-300 h-full flex flex-col">
                <div className={`w-3/4 h-1 ${lane.color} rounded-full mb-6 opacity-70`} />
                <h3 className="text-foreground font-semibold text-lg mb-4">{lane.name}</h3>
                <ul className="space-y-2.5 flex-1">
                  {lane.tasks.map((task) => (
                    <li key={task.label} className="flex items-start gap-2.5">
                      <span
                        className={`mt-1 w-3.5 h-3.5 rounded border flex-shrink-0 flex items-center justify-center ${
                          task.done
                            ? "bg-primary/20 border-primary/40"
                            : "border-border bg-background"
                        }`}
                      >
                        {task.done && (
                          <svg width="8" height="8" viewBox="0 0 12 12" fill="none" className="text-primary">
                            <path d="M2.5 6.5L5 9L9.5 3.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                          </svg>
                        )}
                      </span>
                      <span
                        className={`text-sm leading-snug ${
                          task.done ? "text-muted-foreground line-through" : "text-foreground"
                        }`}
                      >
                        {task.label}
                      </span>
                    </li>
                  ))}
                </ul>
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
