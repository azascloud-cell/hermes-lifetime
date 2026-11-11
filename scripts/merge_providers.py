#!/usr/bin/env python3
"""Force Free.ai as default custom endpoint. Removes ninerouter/9router."""
import os, sys, pathlib
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "-q"])
    import yaml

HERMES_HOME = pathlib.Path(os.environ.get("HERMES_HOME", pathlib.Path.home() / ".hermes"))
LIVE = HERMES_HOME / "config.yaml"

BASE = "https://api.free.ai/v1"
KEY_ENV = "FREE_AI_API_KEY"
DEFAULT_MODEL = "qwen7b"

def main():
    data = {}
    if LIVE.exists():
        try:
            data = yaml.safe_load(LIVE.read_text()) or {}
        except Exception:
            data = {}

    model = data.setdefault("model", {})
    model["default"] = DEFAULT_MODEL
    model["provider"] = "custom"
    model["base_url"] = BASE
    model["key_env"] = KEY_ENV
    model["api_mode"] = "chat_completions"
    model["context_length"] = 128000

    # Remove old ninerouter / 9router entries
    if isinstance(model.get("providers"), dict):
        model["providers"].pop("9router", None)
        model["providers"].pop("ninerouter", None)

    providers = data.setdefault("providers", {})
    if not isinstance(providers, dict):
        providers = {}
        data["providers"] = providers
    providers.pop("ninerouter", None)
    providers.pop("9router", None)
    providers["freeai"] = {
        "api": BASE,
        "key_env": KEY_ENV,
        "transport": "chat_completions",
    }

    data.setdefault("memory", {})
    data["memory"]["memory_enabled"] = True
    data["memory"]["user_profile_enabled"] = True

    LIVE.parent.mkdir(parents=True, exist_ok=True)
    LIVE.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
    print("FORCED provider=custom base_url=%s key_env=%s default=%s" % (BASE, KEY_ENV, DEFAULT_MODEL))
    print("ninerouter removed; freeai registered")
    print("DONE")

if __name__ == "__main__":
    main()
