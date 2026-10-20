#!/usr/bin/env python3
"""Run trigger evaluation for a skill description.

Tests whether a skill's description causes opencode to trigger (read the skill)
for a set of queries. Outputs results as JSON.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

from scripts.utils import parse_skill_md


def find_project_root() -> Path:
    """Find the project root by walking up from cwd looking for .opencode/.

    Mimics how opencode discovers its project root, so the skill directory
    we create ends up where `opencode run` will look for it.
    """
    current = Path.cwd()
    for parent in [current, *current.parents]:
        if (parent / ".opencode").is_dir():
            return parent
    return current


def run_single_query(
    query: str,
    skill_name: str,
    skill_description: str,
    timeout: int,
    project_root: str,
    model: str | None = None,
) -> bool:
    """Run a single query and return whether the skill was triggered.

    Creates a throwaway skill at .opencode/skills/<name>-skill-<id>/SKILL.md so it
    appears in opencode's available-skills list, then runs `opencode run
    --format json` with the raw query.

    Trigger detection reads the raw JSON event stream. A trigger is a `tool_use`
    event whose part.tool is "skill" and whose part.state.input.name is the
    throwaway skill name. opencode also emits a tool_use event when the model
    reaches for some *other* tool, which means it declined to load a skill --
    that case returns False immediately rather than waiting for the run to end.
    """
    unique_id = uuid.uuid4().hex[:8]
    clean_name = f"{skill_name}-skill-{unique_id}"
    skill_dir = Path(project_root) / ".opencode" / "skills" / clean_name
    skill_file = skill_dir / "SKILL.md"

    try:
        skill_dir.mkdir(parents=True, exist_ok=True)
        # Quote the description so colons and quotes cannot break the YAML.
        skill_file.write_text(
            "---\n"
            f"name: {clean_name}\n"
            'description: >-\n'
            f"  {skill_description}\n"
            "---\n\n"
            f"# {clean_name}\n\n"
            f"This skill handles: {skill_description}\n"
        )

        cmd = ["opencode", "run", "--format", "json"]
        if model:
            cmd.extend(["--model", model])
        cmd.append(query)

        # --pure keeps an unrelated user plugin from mutating the run, and the
        # agent is pinned to build so the skill decision is the agent's alone.
        cmd.insert(2, "--pure")

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=project_root,
            env=os.environ.copy(),
        )

        if process.stdout is None:  # stdout=PIPE guarantees this
            process.kill()
            process.wait()
            return False

        start_time = time.time()

        try:
            for raw_line in process.stdout:
                if time.time() - start_time > timeout:
                    break
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if event.get("type") != "tool_use":
                    continue

                part = event.get("part") or {}
                tool_name = part.get("tool", "")
                state = part.get("state") or {}

                if tool_name == "skill":
                    invoked = (state.get("input") or {}).get("name", "")
                    return invoked == clean_name

                # The model picked a different tool. Treat the whole run as a
                # non-trigger instead of waiting for it to finish.
                return False
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

        return False
    finally:
        if skill_file.exists():
            skill_file.unlink()
        try:
            skill_dir.rmdir()
        except OSError:
            pass


def run_eval(
    eval_set: list[dict],
    skill_name: str,
    description: str,
    num_workers: int,
    timeout: int,
    project_root: Path,
    runs_per_query: int = 1,
    trigger_threshold: float = 0.5,
    model: str | None = None,
) -> dict:
    """Run the full eval set and return results."""
    results = []

    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        future_to_info = {}
        for item in eval_set:
            for run_idx in range(runs_per_query):
                future = executor.submit(
                    run_single_query,
                    item["query"],
                    skill_name,
                    description,
                    timeout,
                    str(project_root),
                    model,
                )
                future_to_info[future] = (item, run_idx)

        query_triggers: dict[str, list[bool]] = {}
        query_items: dict[str, dict] = {}
        for future in as_completed(future_to_info):
            item, _ = future_to_info[future]
            query = item["query"]
            query_items[query] = item
            if query not in query_triggers:
                query_triggers[query] = []
            try:
                query_triggers[query].append(future.result())
            except Exception as e:
                print(f"Warning: query failed: {e}", file=sys.stderr)
                query_triggers[query].append(False)

    for query, triggers in query_triggers.items():
        item = query_items[query]
        trigger_rate = sum(triggers) / len(triggers)
        should_trigger = item["should_trigger"]
        if should_trigger:
            did_pass = trigger_rate >= trigger_threshold
        else:
            did_pass = trigger_rate < trigger_threshold
        results.append({
            "query": query,
            "should_trigger": should_trigger,
            "trigger_rate": trigger_rate,
            "triggers": sum(triggers),
            "runs": len(triggers),
            "pass": did_pass,
        })

    passed = sum(1 for r in results if r["pass"])
    total = len(results)

    return {
        "skill_name": skill_name,
        "description": description,
        "results": results,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": total - passed,
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Run trigger evaluation for a skill description")
    parser.add_argument("--eval-set", required=True, help="Path to eval set JSON file")
    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
    parser.add_argument("--description", default=None, help="Override description to test")
    parser.add_argument("--num-workers", type=int, default=10, help="Number of parallel workers")
    parser.add_argument("--timeout", type=int, default=30, help="Timeout per query in seconds")
    parser.add_argument("--runs-per-query", type=int, default=3, help="Number of runs per query")
    parser.add_argument("--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold")
    parser.add_argument("--model", default=None, help="Model for opencode run, as provider/model (default: user's configured model)")
    parser.add_argument("--verbose", action="store_true", help="Print progress to stderr")
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text())
    skill_path = Path(args.skill_path)

    if not (skill_path / "SKILL.md").exists():
        print(f"Error: No SKILL.md found at {skill_path}", file=sys.stderr)
        sys.exit(1)

    name, original_description, content = parse_skill_md(skill_path)
    description = args.description or original_description
    project_root = find_project_root()

    if args.verbose:
        print(f"Evaluating: {description}", file=sys.stderr)

    output = run_eval(
        eval_set=eval_set,
        skill_name=name,
        description=description,
        num_workers=args.num_workers,
        timeout=args.timeout,
        project_root=project_root,
        runs_per_query=args.runs_per_query,
        trigger_threshold=args.trigger_threshold,
        model=args.model,
    )

    if args.verbose:
        summary = output["summary"]
        print(f"Results: {summary['passed']}/{summary['total']} passed", file=sys.stderr)
        for r in output["results"]:
            status = "PASS" if r["pass"] else "FAIL"
            rate_str = f"{r['triggers']}/{r['runs']}"
            print(f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
