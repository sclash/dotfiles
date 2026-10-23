---
name: webapp-testing
description: Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.
license: Complete terms in LICENSE.txt
---

# Web Application Testing

To test local web applications, write native Python Playwright scripts.

**Helper Scripts Available**:
- `scripts/with_server.py` - Manages server lifecycle (supports multiple servers)

**Always run scripts with `--help` first** to see usage. DO NOT read the source until you try running the script first and find that a customized solution is abslutely necessary. These scripts can be very large and thus pollute your context window. They exist to be called directly as black-box scripts rather than ingested into your context window.

## Backend availability

Playwright needs a Python environment and a Chromium binary. Neither is in the ambient
environment on this machine, so **do not** write bare `python script.py` — it fails with
`ModuleNotFoundError: No module named 'playwright'`.

**Preferred when available:** the `playwright` MCP server, configured in
`~/.config/opencode/opencode.json`. If it is enabled in this session its tools are in your
tool list and you can drive the browser with them directly, skipping script writing for
simple inspect/screenshot/navigate tasks.

**Fallback: isolated Playwright via `uv`, driving the system Chromium.**

```bash
uv run --with playwright python your_script.py
```

On this host:

- No `LD_LIBRARY_PATH` prefix is needed: `uv` uses uv-managed Python here
  (`python-preference = "managed"`), so Playwright's numpy/greenlet wheels load Ubuntu's
  `libstdc++` directly.
- `executable_path` must point at the Nix-provided Chromium (`~/.nix-profile/bin/chromium`)
  in the launch call, plus `--no-sandbox`. Playwright's own downloaded Chromium build needs apt
  system libraries (`libnss3`, `libnspr4`, and friends) that this host does not have. The
  Nix-built Chromium has all of its dependencies satisfied already. Do not run
  `playwright install` — it downloads browsers that cannot be launched here.

`scripts/with_server.py` itself only uses the standard library, so it can be launched with a
bare `python`. It is the *automation script* it spawns that needs the `uv` runner.

## Decision Tree: Choosing Your Approach

```
User task → Is it static HTML?
    ├─ Yes → Read HTML file directly to identify selectors
    │         ├─ Success → Write Playwright script using selectors
    │         └─ Fails/Incomplete → Treat as dynamic (below)
    │
    └─ No (dynamic webapp) → Is the server already running?
        ├─ No → Run: python scripts/with_server.py --help
        │        Then use the helper + write simplified Playwright script
        │
        └─ Yes → Reconnaissance-then-action:
            1. Navigate and wait for networkidle
            2. Take screenshot or inspect DOM
            3. Identify selectors from rendered state
            4. Execute actions with discovered selectors
```

## Example: Using with_server.py

To start a server, run `--help` first, then use the helper:

**Single server:**
```bash
python scripts/with_server.py --server "npm run dev" --port 5173 -- \
  uv run --with playwright python your_automation.py
```

**Multiple servers (e.g., backend + frontend):**
```bash
python scripts/with_server.py \
  --server "cd backend && python server.py" --port 3000 \
  --server "cd frontend && npm run dev" --port 5173 \
  -- uv run --with playwright python your_automation.py
```

To create an automation script, include only Playwright logic (servers are managed automatically).
Always launch Chromium through the system binary:
```python
import os

from playwright.sync_api import sync_playwright

CHROMIUM = os.path.expanduser("~/.nix-profile/bin/chromium")

with sync_playwright() as p:
    # executable_path + --no-sandbox are required: Playwright's bundled
    # Chromium cannot resolve its shared-library deps on this host.
    browser = p.chromium.launch(headless=True, executable_path=CHROMIUM,
                                args=["--no-sandbox", "--disable-dev-shm-usage"])
    page = browser.new_page()
    page.goto('http://localhost:5173') # Server already running and ready
    page.wait_for_load_state('networkidle') # CRITICAL: Wait for JS to execute
    # ... your automation logic
    browser.close()
```

## Reconnaissance-Then-Action Pattern

1. **Inspect rendered DOM**:
   ```python
   page.screenshot(path='/tmp/inspect.png', full_page=True)
   content = page.content()
   page.locator('button').all()
   ```

2. **Identify selectors** from inspection results

3. **Execute actions** using discovered selectors

## Common Pitfall

❌ **Don't** inspect the DOM before waiting for `networkidle` on dynamic apps
✅ **Do** wait for `page.wait_for_load_state('networkidle')` before inspection

## Best Practices

- **Use bundled scripts as black boxes** - To accomplish a task, consider whether one of the scripts available in `scripts/` can help. These scripts handle common, complex workflows reliably without cluttering the context window. Use `--help` to see usage, then invoke directly. 
- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Use descriptive selectors: `text=`, `role=`, CSS selectors, or IDs
- Add appropriate waits: `page.wait_for_selector()` or `page.wait_for_timeout()`

## Reference Files

- **examples/** - Examples showing common patterns:
  - `element_discovery.py` - Discovering buttons, links, and inputs on a page
  - `static_html_automation.py` - Using file:// URLs for local HTML
  - `console_logging.py` - Capturing console logs during automation