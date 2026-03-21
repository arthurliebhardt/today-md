import { ScrollReveal } from "./ScrollReveal";

export function MarkdownSection() {
  return (
    <section id="markdown" className="py-24 md:py-32 bg-section-alt">
      <div className="max-w-5xl mx-auto px-6">
        <div className="grid md:grid-cols-2 gap-16 items-start">
          <ScrollReveal>
            <p className="text-primary text-sm font-medium tracking-wide uppercase mb-3">Markdown-native</p>
            <h2 className="font-display text-3xl md:text-4xl tracking-[-0.02em] leading-[1.15] text-foreground mb-6">
              Your notes are real files.
            </h2>
            <p className="text-muted-foreground text-base leading-relaxed text-pretty mb-6">
              Every note you write is automatically mirrored as a <code className="text-foreground bg-background px-1.5 py-0.5 rounded text-[13px] border border-border/60">.md</code> file on disk. Open them in any editor. Grep them from the terminal. They're yours.
            </p>
            <ul className="space-y-3 text-sm">
              {[
                "Standard Markdown with full formatting support",
                "Automatic file mirroring — notes sync to disk in real time",
                "Export tasks as JSON, notes as Markdown, or both",
                "No proprietary format, no lock-in, no conversion needed",
              ].map((item) => (
                <li key={item} className="flex items-start gap-2.5 text-muted-foreground">
                  <span className="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0" />
                  <span className="text-pretty leading-relaxed">{item}</span>
                </li>
              ))}
            </ul>
          </ScrollReveal>

          <ScrollReveal delay={0.15}>
            <div className="rounded-xl border border-border/60 bg-background p-5 shadow-sm font-mono text-[13px] leading-relaxed text-foreground/80">
              <div className="flex items-center gap-2 mb-4 text-muted-foreground text-xs">
                <span className="w-2.5 h-2.5 rounded-full bg-[#FF5F57]" />
                <span className="w-2.5 h-2.5 rounded-full bg-[#FEBC2E]" />
                <span className="w-2.5 h-2.5 rounded-full bg-[#28C840]" />
                <span className="ml-2">api-redesign.md</span>
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
