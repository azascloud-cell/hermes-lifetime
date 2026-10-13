#!/usr/bin/env python3
"""Force 9router as primary with VALID model ids from the live /v1/models list."""
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
    "9router": {
        "base_url": "http://38.49.213.154:2141/v1",
        "api_key_env": "NINEROUTER_API_KEY",
        "models": [
            {"id": "nero", "alias": "nero"},
            {"id": "agnes-2.5-flash/muse-spark-1.3-contributor-free", "alias": "muse-free"},
            {"id": "agnes-2.5-flash/claude-sonnet-5", "alias": "claude-sonnet-5"},
            {"id": "agnes-2.5-flash/claude-opus-5", "alias": "claude-opus-5"},
            {"id": "agnes-2.5-flash/gpt-6-astra", "alias": "gpt-6-astra"},
            {"id": "agnes-2.5-flash/kimi-k3", "alias": "kimi-k3"},
            {"id": "agnes-2.5-flash/gemini-3.8-flash-high", "alias": "gemini-flash"},
            {"id": "agnes-2.5-flash/deepseek-v4.1-flash", "alias": "deepseek-flash"},
        ],
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
    data = {}
    if LIVE.exists():
        try:
            data = yaml.safe_load(LIVE.read_text()) or {}
        except Exception:
            data = {}

    model = data.setdefault("model", {})
    existing = model.get("providers") if isinstance(model.get("providers"), dict) else {}
    model["providers"] = {**existing, **PROVIDERS}
    model["providers"]["9router"] = PROVIDERS["9router"]  # force

    model["provider"] = "9router"
    # NEVER leave gpt-4o-mini — it does not exist on 9router
    bad = {"gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo", "gemma4:31b"}
    if not model.get("default") or model.get("default") in bad:
        model["default"] = "nero"
    model["api_mode"] = "chat_completions"

    data.setdefault("memory", {})
    data["memory"]["memory_enabled"] = True
    data["memory"]["user_profile_enabled"] = True

    LIVE.parent.mkdir(parents=True, exist_ok=True)
    LIVE.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
    print("provider=9router default=", model["default"])
    print("models:", [m["id"] for m in PROVIDERS["9router"]["models"]])
    print("DONE")

if __name__ == "__main__":
    main()
