---
name: pterodactyl-bot-deployment
description: \"Deploy Python bots to Pterodactyl with env management.\"
version: 1.0.0
author: Hermes
---

# Pterodactyl Bot Deployment

Guidelines for deploying Python bots to Pterodactyl using Generic Python Eggs, specifically focusing on environment variable handling and dependency resolution.

## Procedure

1. **Dependency Preparation**: 
   - Use a `requirements.txt` with pinned versions.
   - If deploying to a modern environment (e.g., Python 3.12+), be aware of Pydantic v2 migrations. Use `pydantic-settings` instead of `pydantic.BaseSettings`.

2. **Deployment Workflow**:
   - Package project as a ZIP (exclude `venv`, `__pycache__`, `.git`, `.env`).
   - Upload to Pterodactyl Files tab $\rightarrow$ Unarchive.
   - Set Startup file (e.g., `app.py`).

3. **Environment Configuration**:
   - **Primary Method**: Use the Pterodactyl **Startup $\rightarrow$ Environment Variables** tab. This injects variables directly into the OS environment.
   - **Fallback Method**: If the panel lacks custom env vars, create a `.env` file in the root directory.
   - **Force Loading**: To ensure `.env` is read regardless of the Pterodactyl image configuration, call `load_dotenv(dotenv_path=\".env\")` at the very top of the entry point script (`app.py`) before any config imports.

## Pitfalls

- **Pydantic v1 vs v2**: Pydantic v2 moved `BaseSettings` to the `pydantic-settings` package. Importing `BaseSettings` from `pydantic` in v2 environments causes a `PydanticImportError`. Always use `from pydantic_settings import BaseSettings`.
- **Env Var Visibility**: Pterodactyl environments can be inconsistent. If `.env` is not being read, it is usually because the working directory (`cwd`) of the container differs from the file location. Explicitly passing `dotenv_path` to `load_dotenv` fixes this.
- **Python 3.14/Experimental**: Be cautious with cutting-edge Python versions (like 3.14) in Pterodactyl eggs, as binary wheels for packages like `pydantic-core` or `pandas` may not be available, leading to expensive and potentially failing native builds from source.
- **Pterodactyl Startup Sequence**: Pterodactyl often runs `pip install -r requirements.txt` before executing the app. If this fails, the bot will crash before the app logic even starts.
