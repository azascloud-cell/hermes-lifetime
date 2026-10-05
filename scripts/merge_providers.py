#!/usr/bin/env python3
"""Force-register all providers with base_url into live config. Runs every session start."""
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
    "xkiro": {
        "base_url": "https://xkiro.com/v1",
        "api_key_env": "XKIRO_API_KEY",
        "models": [{"id": "qwen/qwen3.8-omni-flash:free", "alias": "xkiro"}],
    },
    "groq": {
        "base_url": "https://api.groq.com/openai/v1",
        "api_key_env": "GROQ_API_KEY",
        "models": [
            {"id": "openai/gpt-oss-120b", "alias": "groq-oss"},
            {"id": "openai/gpt-oss-20b", "alias": "groq-oss-20b"},
            {"id": "qwen/qwen3.8-27b", "alias": "groq-qwen"},
        ],
    },
    "aisub-minimax": {
        "base_url": "http://66.135.18.180:8080/v1",
        "api_key_env": "AISUBSCRIPTION_API_KEY",
        "models": [{"id": "MiniMaxAI/MiniMax-M2.7", "alias": "aisub-minimax"}],
    },
    "aisub-qwen": {
        "base_url": "http://43.179.177.126:8000/v1",
        "api_key_env": "AISUBSCRIPTION_API_KEY",
        "models": [{"id": "Qwen3.5-122B-A10B", "alias": "aisub-qwen"}],
    },
    "aisub-gemma": {
        "base_url": "http://36.137.226.29:8000/v1",
        "api_key_env": "AISUBSCRIPTION_API_KEY",
        "models": [{"id": "gemma-4-31b-it", "alias": "aisub-gemma"}],
    },
    "miarouter": {
        "base_url": "https://miarouter.online/v1",
        "api_key_env": "MIAROUTER_API_KEY",
        "models": [
            {"id": "claude-fable-5-1", "alias": "claude-fable-5-1"},
            {"id": "claude-opus-5", "alias": "claude-opus-5"},
            {"id": "claude-sonnet-5", "alias": "claude-sonnet-5"},
            {"id": "gpt-6-astra", "alias": "gpt-6-astra"},
            {"id": "kimi-k3", "alias": "kimi-k3"},
        ],
    },
}

def main():
    if LIVE.exists():
        data = yaml.safe_load(LIVE.read_text()) or {}
    else:
        data = {}
        print("no live config — creating")

    model = data.setdefault("model", {})
    model["providers"] = dict(PROVIDERS)
    model.setdefault("default", "gemma4:31b")
    model.setdefault("provider", "ollama-cloud")
    model.setdefault("api_mode", "chat_completions")

    LIVE.parent.mkdir(parents=True, exist_ok=True)
    LIVE.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))

    check = yaml.safe_load(LIVE.read_text())
    keys = list(check["model"]["providers"].keys())
    print("Providers registered:", keys)
    for k, v in check["model"]["providers"].items():
        print(f"  {k}: {v.get('base_url')} key_env={v.get('api_key_env')}")
    assert "miarouter" in keys and "aisub-gemma" in keys
    print("DONE — providers forced")

if __name__ == "__main__":
    main()
