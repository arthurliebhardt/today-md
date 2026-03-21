import { motion } from "framer-motion";
import appMockup from "@/assets/app-mockup.png";

export function Hero() {
  return (
    <section className="relative pt-32 pb-16 md:pt-40 md:pb-24 overflow-hidden">
      <div className="max-w-5xl mx-auto px-6">
        {/* Text */}
        <div className="max-w-2xl">
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.2 }}
            className="text-primary font-semibold tracking-tight text-lg mb-4"
          >
            today-md
          </motion.p>
          <motion.h1
            initial={{ opacity: 0, y: 16, filter: "blur(4px)" }}
            animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
            transition={{ duration: 0.7, delay: 0.3, ease: [0.16, 1, 0.3, 1] }}
            className="font-display text-5xl md:text-[3.75rem] leading-[1.05] tracking-[-0.025em] text-foreground text-balance mb-5"
          >
            Plan the day<br />in Markdown.
          </motion.h1>
          <motion.p
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.45, ease: [0.16, 1, 0.3, 1] }}
            className="text-muted-foreground text-lg leading-relaxed text-pretty max-w-lg mb-8"
          >
            A native macOS task manager for turning notes into action — across Today, This Week, and Backlog.
          </motion.p>
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.6, ease: [0.16, 1, 0.3, 1] }}
            className="flex flex-wrap gap-3"
          >
            <a
              href="#download"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-primary text-primary-foreground text-sm font-medium shadow-[0_1px_3px_rgba(0,0,0,0.12),0_4px_12px_rgba(229,138,43,0.2)] hover:shadow-[0_2px_6px_rgba(0,0,0,0.15),0_6px_20px_rgba(229,138,43,0.25)] transition-all duration-200 active:scale-[0.97]"
            >
              <AppleIcon />
              Download for macOS
            </a>
            <a
              href="https://github.com"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border border-border text-foreground text-sm font-medium hover:bg-muted/50 transition-all duration-200 active:scale-[0.97]"
            >
              View on GitHub
            </a>
          </motion.div>
        </div>

        {/* App mockup */}
        <motion.div
          initial={{ opacity: 0, y: 30, filter: "blur(6px)" }}
          animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          transition={{ duration: 0.9, delay: 0.7, ease: [0.16, 1, 0.3, 1] }}
          className="mt-16 md:mt-20"
        >
          <div className="rounded-xl overflow-hidden shadow-[0_8px_40px_rgba(0,0,0,0.08),0_2px_8px_rgba(0,0,0,0.04)] border border-border/60">
            <img
              src={appMockup}
              alt="today-md app showing three planning lanes — Today, This Week, and Backlog — with task cards and a Markdown notes panel"
              className="w-full h-auto block"
              loading="eager"
            />
          </div>
        </motion.div>
      </div>
    </section>
  );
}

function AppleIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
    </svg>
  );
}
