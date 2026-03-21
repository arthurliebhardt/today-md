import { ScrollReveal } from "./ScrollReveal";

export function MarkdownSection() {
  return (
    <section id="markdown" className="py-28 md:py-36 border-t border-border/40">
      <div className="max-w-[1120px] mx-auto px-6">
        <ScrollReveal>
          <div className="text-center max-w-2xl mx-auto mb-20">
            <p className="text-primary text-sm font-semibold tracking-wide uppercase mb-4">Markdown-native</p>
            <h2 className="text-foreground text-3xl md:text-5xl font-bold tracking-[-0.035em] leading-[1.1] text-balance">
              Your notes are real files.
            </h2>
          </div>
        </ScrollReveal>

        <div className="grid md:grid-cols-2 gap-16 items-start">
          <ScrollReveal>
            <p className="text-muted-foreground text-base leading-relaxed text-pretty mb-8">
              Every note you write is automatically mirrored as a <code className="text-foreground bg-muted px-1.5 py-0.5 rounded-md text-[13px]">.md</code> file on disk. Open them in any editor. Grep them from the terminal. They're yours.
            </p>
            <ul className="space-y-4 text-sm">
              {[
                "Standard Markdown with full formatting support",
                "Automatic file mirroring — notes sync to disk in real time",
                "Export tasks as JSON, notes as Markdown, or both",
                "No proprietary format, no lock-in, no conversion needed",
              ].map((item) => (
                <li key={item} className="flex items-start gap-3 text-muted-foreground">
                  <span className="mt-2 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0" />
                  <span className="text-pretty leading-relaxed">{item}</span>
                </li>
              ))}
            </ul>
          </ScrollReveal>

          <ScrollReveal delay={0.15}>
            <div className="rounded-2xl border border-border/50 bg-card p-6 font-mono text-[13px] leading-relaxed text-foreground/80 shadow-sm">
              <div className="flex items-center gap-2 mb-5 text-muted-foreground text-xs">
                <span className="w-3 h-3 rounded-full bg-destructive/60" />
                <span className="w-3 h-3 rounded-full bg-primary/60" />
                <span className="w-3 h-3 rounded-full bg-secondary/60" />
                <span className="ml-2 font-sans">api-redesign.md</span>
              </div>
              <pre className="whitespace-pre-wrap text-pretty">
{`# API Redesign Notes

## Goals
- Simplify auth flow for v2
- Reduce response payload by ~40%
- Deprecate legacy XML endpoints

## Open Questions
- [ ] Confirm rate-limit strategy
- [x] Align on versioning scheme
- [ ] Review error response format

> Ship the breaking changes in March.
> Backfill docs before the release.`}
              </pre>
            </div>
          </ScrollReveal>
        </div>
      </div>
    </section>
  );
}
