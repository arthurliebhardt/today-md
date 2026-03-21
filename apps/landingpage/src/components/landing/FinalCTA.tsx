import { ScrollReveal } from "./ScrollReveal";

export function FinalCTA() {
  return (
    <section id="download" className="py-28 md:py-36 border-t border-border/40">
      <div className="max-w-[1120px] mx-auto px-6 text-center">
        <ScrollReveal>
          <h2 className="text-foreground text-3xl md:text-5xl font-bold tracking-[-0.035em] leading-[1.1] text-balance mb-5">
            Your tasks, your notes, your machine.
          </h2>
          <p className="text-muted-foreground text-base md:text-lg leading-relaxed max-w-md mx-auto mb-10">
            A calm, local-first planner built for people who think in Markdown.
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <a
              href="#"
              className="inline-flex items-center gap-2 px-7 py-3 rounded-full bg-foreground text-background text-sm font-medium hover:bg-foreground/85 transition-colors duration-150 active:scale-[0.97]"
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
              className="inline-flex items-center gap-2 px-7 py-3 rounded-full border border-border text-foreground text-sm font-medium hover:bg-muted/60 transition-colors duration-150 active:scale-[0.97]"
            >
              View on GitHub
            </a>
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
