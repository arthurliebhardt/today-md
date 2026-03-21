export function Footer() {
  return (
    <footer className="py-8 border-t border-border/40">
      <div className="max-w-[1120px] mx-auto px-6 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-muted-foreground">
        <p>today-md · Built for macOS</p>
        <div className="flex items-center gap-6">
          <a href="https://github.com" className="hover:text-foreground transition-colors duration-150">GitHub</a>
          <a href="#" className="hover:text-foreground transition-colors duration-150">Privacy</a>
          <a href="#" className="hover:text-foreground transition-colors duration-150">Releases</a>
        </div>
      </div>
    </footer>
  );
}
