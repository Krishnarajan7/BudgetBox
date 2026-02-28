from app.achievements.definitions import ACHIEVEMENTS


def evaluate_achievements(stats: dict):
    unlocked = []

    for achievement in ACHIEVEMENTS:
        if achievement["condition"](stats):
            unlocked.append(achievement["id"])

    return unlocked
