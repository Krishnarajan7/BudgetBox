DAILY_REQUIREMENTS = {
    "protein_g": 56,
    "fiber_g": 30,
    "vitamin_a_mcg": 900,
    "vitamin_b12_mcg": 2.4,
    "vitamin_c_mg": 90,
    "vitamin_d_mcg": 15,
    "vitamin_e_mg": 15,
    "vitamin_k_mcg": 120,
    "calcium_mg": 1000,
    "iron_mg": 8,
    "magnesium_mg": 420,
    "potassium_mg": 3400,
    "sodium_mg": 2300,
    "zinc_mg": 11,
}

NUTRIENT_FOOD_SOURCES = {
    "vitamin_c_mg": ["Orange", "Guava", "Lemon", "Strawberry", "Bell Pepper"],
    "iron_mg": ["Spinach", "Lentils", "Chickpeas", "Red Meat", "Pumpkin Seeds"],
    "protein_g": ["Eggs", "Chicken Breast", "Paneer", "Greek Yogurt", "Tofu"],
    "calcium_mg": ["Milk", "Curd", "Cheese", "Sesame Seeds", "Almonds"],
    "fiber_g": ["Oats", "Apple", "Flax Seeds", "Beans", "Vegetables"],
    "vitamin_d_mcg": ["Egg Yolk", "Mushrooms", "Fatty Fish", "Fortified Milk", "Sunlight"],
}

def analyze_nutrient_status(daily_intake: dict):
    deficiencies = []
    excesses = []

    for nutrient, required in DAILY_REQUIREMENTS.items():
        consumed = daily_intake.get(nutrient, 0)

        if consumed < required * 0.75:
            deficiencies.append({
                "nutrient": nutrient,
                "consumed": round(consumed, 2),
                "required": required,
                "status": "deficient",
            })
        elif consumed > required * 1.5:
            excesses.append({
                "nutrient": nutrient,
                "consumed": round(consumed, 2),
                "upper_limit": round(required * 1.5, 2),
                "status": "excess",
            })

    return {
        "deficiencies": deficiencies,
        "excesses": excesses,
    }

def biological_insights(deficiencies: list):
    insights = []
    nutrient_set = {d["nutrient"] for d in deficiencies}

    if "iron_mg" in nutrient_set and "vitamin_c_mg" in nutrient_set:
        insights.append("Iron absorption may be reduced due to low Vitamin C intake")

    if "vitamin_d_mcg" in nutrient_set and "calcium_mg" in nutrient_set:
        insights.append("Low Vitamin D and Calcium may affect bone health")

    if "fiber_g" in nutrient_set and "potassium_mg" in nutrient_set:
        insights.append("Low fiber and potassium may impact gut and heart health")

    if "protein_g" in nutrient_set:
        insights.append("Low protein intake may affect muscle recovery and immunity")

    if "sodium_mg" in nutrient_set:
        insights.append("Sodium imbalance may affect blood pressure regulation")

    return insights

def suggest_foods(deficiencies: list):
    suggestions = []

    for item in deficiencies:
        nutrient = item["nutrient"]
        foods = NUTRIENT_FOOD_SOURCES.get(nutrient)

        if foods:
            suggestions.append({
                "nutrient": nutrient,
                "recommended_foods": foods[:3],
                "reason": f"Low {nutrient.replace('_', ' ')} intake detected",
            })

    return suggestions

def generate_health_report(daily_intake: dict):
    status = analyze_nutrient_status(daily_intake)
    insights = biological_insights(status["deficiencies"])
    food_suggestions = suggest_foods(status["deficiencies"])

    summary = []

    if status["deficiencies"]:
        summary.append(f"{len(status['deficiencies'])} nutrient deficiencies detected")

    if status["excesses"]:
        summary.append(f"{len(status['excesses'])} nutrients above recommended levels")

    if not summary:
        summary.append("Your nutrient intake looks balanced today")

    return {
        "summary": summary,
        "deficiencies": status["deficiencies"],
        "excesses": status["excesses"],
        "medical_insights": insights,
        "food_suggestions": food_suggestions,
    }
