#!/usr/bin/env python3
"""Register 9router as primary provider + optional fallbacks."""
import os, sys, pathlib
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "-q"])
    import yaml

HERMES_HOME = pathlib.Path(os.environ.get("HERMES_HOME", pathlib.Path.home() / ".hermes"))
LIVE = HERMES_HOME / "config.yaml"

PROVIDERS = {
    # Primary: 9router — models managed on 9router dashboard (no key-hopping)
    "9router": {
        "base_url": "http://38.49.213.154:2141/v1",
        "api_key_env": "NINEROUTER_API_KEY",
    },
    "ollama-cloud": {
        "base_url": "https://ollama.com/v1",
        "api_key_env": "OLLAMA_API_KEY",
    },
    "google": {
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "api_key_env": "GOOGLE_API_KEY",
    },
    "gemini": {
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "api_key_env": "GEMINI_API_KEY",
    },
}

def main():
    if LIVE.exists():
        try:
            data = yaml.safe_load(LIVE.read_text()) or {}
        except Exception:
            data = {}
    else:
        data = {}

    model = data.setdefault("model", {})
    # Keep any existing providers user added, then force our map
    existing = model.get("providers") or {}
    if not isinstance(existing, dict):
        existing = {}
    merged = {**existing, **PROVIDERS}
    # Force 9router base_url always
    merged["9router"] = PROVIDERS["9router"]
    model["providers"] = merged

    # Default to 9router
    model["provider"] = "9router"
    model.setdefault("api_mode", "chat_completions")
    # Default model id — user can change via /model or 9router dashboard routing
    if not model.get("default") or model.get("default") in ("gemma4:31b", "gpt-oss"):
        model["default"] = "gpt-4o-mini"  # placeholder; 9router routes by its dashboard

    data.setdefault("memory", {})
    data["memory"]["memory_enabled"] = True
    data["memory"]["user_profile_enabled"] = True

    LIVE.parent.mkdir(parents=True, exist_ok=True)
    LIVE.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))

    print("Providers:", list(model["providers"].keys()))
    print("Default provider:", model.get("provider"))
    print("9router base_url:", model["providers"]["9router"]["base_url"])
    print("DONE")

if __name__ == "__main__":
    main()
