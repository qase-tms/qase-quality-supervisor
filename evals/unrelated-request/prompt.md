---
tags: [smoke]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Rewrite this Python snippet to use pathlib instead of os.path:

    import os
    def config_path(name):
        return os.path.join(os.path.dirname(__file__), "conf", name + ".yaml")
