import { motion } from "framer-motion";

export function Hero() {
  return (
    <section className="relative pt-28 pb-8 md:pt-36 md:pb-12 overflow-hidden">
      <div className="max-w-[900px] mx-auto px-6">
        {/* Centered headline */}
        <div className="text-center">
          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.15, ease: [0.16, 1, 0.3, 1] }}
            className="text-foreground text-[clamp(2.5rem,7vw,5rem)] font-black tracking-[-0.04em] leading-[1.0] text-balance mb-8">
            
            Plan your <span className="px-2 rounded-md inline-block bg-[#f8b262]">day,</span>{" "}
            <br className="hidden sm:block" />
            not your tooling
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.25, ease: [0.16, 1, 0.3, 1] }}
            className="text-muted-foreground text-lg md:text-xl leading-relaxed max-w-xl mx-auto text-pretty mb-8">
            A native macOS Kanban planner with three time-based lanes. Markdown notes, keyboard shortcuts, zero cloud dependencies. Your tasks stay on your machine.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4, delay: 0.35, ease: [0.16, 1, 0.3, 1] }}
            className="flex flex-wrap justify-center gap-3 mb-16 md:mb-20">
            
            <button
              disabled
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-foreground/40 text-background text-sm font-semibold cursor-not-allowed">
              <AppleIcon />
              Coming Soon
            </button>
            <a
              href="https://github.com/arthurliebhardt/today-md"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border border-border text-foreground text-sm font-semibold hover:bg-muted/60 transition-colors duration-150 active:scale-[0.97]">
              
              View on GitHub
            </a>
          </motion.div>
        </div>

        {/* App mockup — large and dominant */}
        <motion.div
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.45, ease: [0.16, 1, 0.3, 1] }}>
          
          <div className="rounded-3xl overflow-hidden shadow-[0_24px_80px_rgba(0,0,0,0.12),0_4px_20px_rgba(0,0,0,0.06)]">
            <img
              src={appMockup}
              alt="today-md app showing three planning lanes — Today, This Week, and Backlog — with task cards and a Markdown notes panel"
              className="w-full h-auto block"
              loading="eager" />
            
          </div>
        </motion.div>

        {/* Hint text */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.5, delay: 1 }}
          className="text-center text-muted-foreground text-xs mt-6 flex items-center justify-center gap-1.5">
          
          <span className="text-primary">▶</span> A native macOS task manager. Local-first. Open source.
        </motion.p>
      </div>
    </section>);

}

function AppleIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>);

}