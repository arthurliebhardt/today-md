import { motion } from "framer-motion";

export function Navbar() {
  return (
    <motion.nav
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.5, delay: 0.1 }}
      className="fixed top-0 left-0 right-0 z-50 backdrop-blur-md bg-background/80 border-b border-border/50"
    >
      <div className="max-w-5xl mx-auto px-6 h-14 flex items-center justify-between">
        <a href="#" className="text-foreground font-semibold tracking-tight text-[15px]">
          <span className="text-primary">today</span>-md
        </a>
        <div className="hidden sm:flex items-center gap-8 text-[13px] text-muted-foreground">
          <a href="#features" className="hover:text-foreground transition-colors duration-200">Features</a>
          <a href="#workflow" className="hover:text-foreground transition-colors duration-200">Workflow</a>
          <a href="#markdown" className="hover:text-foreground transition-colors duration-200">Markdown</a>
        </div>
        <a
          href="#download"
          className="text-[13px] font-medium text-primary hover:text-primary/80 transition-colors duration-200"
        >
          Download
        </a>
      </div>
    </motion.nav>
  );
}
