import { ReactNode } from "react";
import { AnimatedSidebar } from "./AnimatedSidebar";
import { MobileSidebar } from "./MobileSidebar";
import { Header } from "./Header";

interface AppLayoutProps {
  children: ReactNode;
  title: string;
  subtitle?: string;
}

export function AppLayout({ children, title, subtitle }: AppLayoutProps) {
  return (
    <div className="flex min-h-screen w-full bg-background">
      {/* Desktop animated sidebar */}
      <AnimatedSidebar />
      
      {/* Main content with left margin for desktop sidebar */}
      <div className="flex-1 flex flex-col min-w-0 md:ml-[3.05rem]">
        <Header title={title} subtitle={subtitle} />
        <main className="flex-1 p-6 overflow-auto">
          {children}
        </main>
      </div>
    </div>
  );
}