import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import Auth from "./pages/Auth";
import Settings from "./pages/Settings";
import Tasks from "./pages/Tasks";
import Habits from "./pages/Habits";
import Mood from "./pages/Mood";
import Expenses from "./pages/Expenses";
import Water from "./pages/Water";
import Sleep from "./pages/Sleep";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/auth" element={<Auth />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/tasks" element={<Tasks />} />
          <Route path="/habits" element={<Habits />} />
          <Route path="/mood" element={<Mood />} />
          <Route path="/expenses" element={<Expenses />} />
          <Route path="/water" element={<Water />} />
          <Route path="/sleep" element={<Sleep />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;