from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str
    debug: bool

    host: str
    port: int

    secret_key: str
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    database_url: str

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
