import { Navbar } from "@/components/landing/Navbar";
import { Hero } from "@/components/landing/Hero";
import { WhyDifferent } from "@/components/landing/WhyDifferent";
import { Workflow } from "@/components/landing/Workflow";
import { MarkdownSection } from "@/components/landing/MarkdownSection";
import { SearchBackup } from "@/components/landing/SearchBackup";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { Footer } from "@/components/landing/Footer";

const Index = () => {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <Hero />
      <WhyDifferent />
      <Workflow />
      <MarkdownSection />
      <SearchBackup />
      <FinalCTA />
      <Footer />
    </div>
  );
};

export default Index;
