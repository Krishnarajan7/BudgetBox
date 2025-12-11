import { useState } from "react";
import { Calendar } from "@/components/ui/calender";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { CalendarDays } from "lucide-react";

export function DashboardCalendar() {
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(new Date());

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-base font-medium flex items-center gap-2">
          <CalendarDays className="w-4 h-4 text-primary" />
          Calendar
        </CardTitle>
      </CardHeader>
      <CardContent className="pt-0">
        <Calendar
          selected={selectedDate}
          onSelect={setSelectedDate}
          size="sm"
          className="border-0 shadow-none p-0 max-w-none"
        />
      </CardContent>
    </Card>
  );
}