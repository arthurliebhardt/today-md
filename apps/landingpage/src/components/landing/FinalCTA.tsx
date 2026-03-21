import { ScrollReveal } from "./ScrollReveal";

export function FinalCTA() {
  return (
    <section id="download" className="py-24 md:py-32 bg-section-alt">
      <div className="max-w-5xl mx-auto px-6 text-center">
        <ScrollReveal>
          <h2 className="font-display text-3xl md:text-[2.75rem] tracking-[-0.02em] leading-[1.1] text-foreground mb-4 text-balance">
            Your tasks, your notes,<br />your machine.
          </h2>
          <p className="text-muted-foreground text-base leading-relaxed max-w-md mx-auto mb-8">
            A calm, local-first planner built for people who think in Markdown.
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <a
              href="#"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-lg bg-primary text-primary-foreground text-sm font-medium shadow-[0_1px_3px_rgba(0,0,0,0.12),0_4px_12px_rgba(229,138,43,0.2)] hover:shadow-[0_2px_6px_rgba(0,0,0,0.15),0_6px_20px_rgba(229,138,43,0.25)] transition-all duration-200 active:scale-[0.97]"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              Download for macOS
            </a>
            <a
              href="https://github.com"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-lg border border-border text-foreground text-sm font-medium hover:bg-muted/50 transition-all duration-200 active:scale-[0.97]"
            >
              View on GitHub
            </a>
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
