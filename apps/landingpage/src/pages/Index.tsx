import { Navbar } from "@/components/landing/Navbar";
import { Hero } from "@/components/landing/Hero";
import { FeatureGrid } from "@/components/landing/FeatureGrid";
import { WhyDifferent } from "@/components/landing/WhyDifferent";
import { Workflow } from "@/components/landing/Workflow";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { Footer } from "@/components/landing/Footer";

const Index = () => {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <Hero />
      <FeatureGrid />
      <WhyDifferent />
      <Workflow />
      <FinalCTA />
      <Footer />
    </div>
  );
};

export default Index;
