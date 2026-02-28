ACHIEVEMENTS = [
    {
        "id": "first_task",
        "title": "First Task",
        "condition": lambda stats: stats["total_tasks_completed"] >= 1,
    },
    {
        "id": "task_streak_3",
        "title": "3 Day Task Streak",
        "condition": lambda stats: stats["task_streak"]["current_streak"] >= 3,
    },
    {
        "id": "first_habit",
        "title": "First Habit",
        "condition": lambda stats: stats["total_habits_completed"] >= 1,
    },
    {
        "id": "habit_streak_7",
        "title": "7 Day Habit Streak",
        "condition": lambda stats: stats["habit_streak"]["current_streak"] >= 7,
    },
    {
        "id": "first_expense",
        "title": "First Expense",
        "condition": lambda stats: stats["total_expenses"] > 0,
    },
]
