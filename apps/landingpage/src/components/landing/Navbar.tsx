import { motion } from "framer-motion";

export function Navbar() {
  return (
    <motion.nav
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.4 }}
      className="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-xl border-b border-border/40"
    >
      <div className="max-w-[1120px] mx-auto px-6 h-14 flex items-center justify-between">
        <a href="#" className="text-foreground font-semibold text-[15px] tracking-tight">
          today-md
        </a>
        <div className="hidden sm:flex items-center gap-8 text-[13px] text-muted-foreground font-medium">
          <a href="#features" className="hover:text-foreground transition-colors duration-150">Features</a>
          <a href="#workflow" className="hover:text-foreground transition-colors duration-150">Workflow</a>
          <a href="#markdown" className="hover:text-foreground transition-colors duration-150">Markdown</a>
        </div>
        <a
          href="#download"
          className="text-[13px] font-medium px-4 py-1.5 rounded-full bg-foreground text-background hover:bg-foreground/85 transition-colors duration-150 active:scale-[0.97]"
        >
          Download
        </a>
      </div>
    </motion.nav>
  );
}
