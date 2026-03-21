export function Footer() {
  return (
    <footer className="py-8 border-t border-border">
      <div className="max-w-5xl mx-auto px-6 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-muted-foreground">
        <p>
          <span className="text-primary font-medium">today</span>-md · Built for macOS
        </p>
        <div className="flex items-center gap-6">
          <a href="https://github.com" className="hover:text-foreground transition-colors duration-200">GitHub</a>
          <a href="#" className="hover:text-foreground transition-colors duration-200">Privacy</a>
          <a href="#" className="hover:text-foreground transition-colors duration-200">Releases</a>
        </div>
      </div>
    </footer>
  );
}
