from sqlalchemy import ForeignKey, Date, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from datetime import date

from app.core.database import Base


class FoodLog(Base):
    __tablename__ = "food_logs"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    food_id: Mapped[int] = mapped_column(ForeignKey("food_nutrient_profiles.id"))
    quantity_g: Mapped[float] = mapped_column(Float)
    consumed_at: Mapped[date] = mapped_column(Date)

    food = relationship("FoodNutrientProfile")
