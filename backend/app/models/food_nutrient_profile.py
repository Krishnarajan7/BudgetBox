from sqlalchemy import String, Float
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

class FoodNutrientProfile(Base):
    __tablename__ = "food_nutrient_profiles"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), unique=True, index=True)

    # Energy & macronutrients (per 100g)
    calories_kcal: Mapped[float] = mapped_column(Float)
    protein_g: Mapped[float] = mapped_column(Float)
    carbs_g: Mapped[float] = mapped_column(Float)
    fat_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[float] = mapped_column(Float)

    # Fat composition
    saturated_fat_g: Mapped[float] = mapped_column(Float)
    monounsaturated_fat_g: Mapped[float] = mapped_column(Float)
    polyunsaturated_fat_g: Mapped[float] = mapped_column(Float)
    omega_3_g: Mapped[float] = mapped_column(Float)
    omega_6_g: Mapped[float] = mapped_column(Float)

    # Vitamins
    vitamin_a_mcg: Mapped[float] = mapped_column(Float)
    vitamin_b1_mg: Mapped[float] = mapped_column(Float)
    vitamin_b2_mg: Mapped[float] = mapped_column(Float)
    vitamin_b3_mg: Mapped[float] = mapped_column(Float)
    vitamin_b5_mg: Mapped[float] = mapped_column(Float)
    vitamin_b6_mg: Mapped[float] = mapped_column(Float)
    vitamin_b9_folate_mcg: Mapped[float] = mapped_column(Float)
    vitamin_b12_mcg: Mapped[float] = mapped_column(Float)
    vitamin_c_mg: Mapped[float] = mapped_column(Float)
    vitamin_d_mcg: Mapped[float] = mapped_column(Float)
    vitamin_e_mg: Mapped[float] = mapped_column(Float)
    vitamin_k_mcg: Mapped[float] = mapped_column(Float)

    # Minerals
    calcium_mg: Mapped[float] = mapped_column(Float)
    iron_mg: Mapped[float] = mapped_column(Float)
    magnesium_mg: Mapped[float] = mapped_column(Float)
    phosphorus_mg: Mapped[float] = mapped_column(Float)
    potassium_mg: Mapped[float] = mapped_column(Float)
    sodium_mg: Mapped[float] = mapped_column(Float)
    zinc_mg: Mapped[float] = mapped_column(Float)
    copper_mg: Mapped[float] = mapped_column(Float)
    manganese_mg: Mapped[float] = mapped_column(Float)
    selenium_mcg: Mapped[float] = mapped_column(Float)
