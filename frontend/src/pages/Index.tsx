import Hero from "@/components/ui/neural-network-hero";

const Index = () => {
  return (
    <div className="w-screen h-screen flex flex-col relative">
      <Hero 
        title="Track your life, beautifully."
        description="BudgetBox helps you monitor tasks, habits, mood, expenses, water intake, and sleep — all in one elegant, minimal dashboard."
        badgeText="Personal Tracking"
        badgeLabel="BudgetBox"
        microDetails={["Tasks", "Habits", "Expenses", "Sleep", "Mood", "Water"]}
      />
    </div>
  );
};

export default Index;