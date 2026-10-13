#!/usr/bin/env python3
"""Force 9router via Hermes official custom endpoint format.

NOT model.providers.9router (unknown to Hermes runtime).
Use: model.provider=custom + base_url + key_env
Plus top-level providers.ninerouter for named custom.
"""
import os, sys, pathlib
try:
    import yaml
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "-q"])
    import yaml

HERMES_HOME = pathlib.Path(os.environ.get("HERMES_HOME", pathlib.Path.home() / ".hermes"))
LIVE = HERMES_HOME / "config.yaml"

BASE = "http://38.49.213.154:2141/v1"
KEY_ENV = "NINEROUTER_API_KEY"

def main():
    data = {}
    if LIVE.exists():
        try:
            data = yaml.safe_load(LIVE.read_text()) or {}
        except Exception:
            data = {}

    # Primary: official custom endpoint
    model = data.setdefault("model", {})
    model["default"] = "nero"
    model["provider"] = "custom"
    model["base_url"] = BASE
    model["key_env"] = KEY_ENV
    model["api_mode"] = "chat_completions"
    model["context_length"] = 128000

    # Strip broken model.providers.9router if present (causes Unknown provider)
    if isinstance(model.get("providers"), dict):
        model["providers"].pop("9router", None)

    # Named custom under top-level providers: (docs format)
    providers = data.setdefault("providers", {})
    if not isinstance(providers, dict):
        providers = {}
        data["providers"] = providers
    providers["ninerouter"] = {
        "api": BASE,
        "key_env": KEY_ENV,
        "transport": "chat_completions",
    }

    data.setdefault("memory", {})
    data["memory"]["memory_enabled"] = True
    data["memory"]["user_profile_enabled"] = True

    LIVE.parent.mkdir(parents=True, exist_ok=True)
    LIVE.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
    print("FORCED provider=custom base_url=%s key_env=%s default=nero" % (BASE, KEY_ENV))
    print("named providers.ninerouter registered")
    print("DONE")

if __name__ == "__main__":
    main()
