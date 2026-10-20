## EVAL: planner

### Capability Evals
1. Can create a detailed implementation plan from a feature request
2. Can identify risks, dependencies, and blockers before implementation
3. Can break down complex features into phased implementation steps

### Success Criteria
- pass@3 > 90% for capability evals
- Output includes: requirements restatement, implementation phases, dependencies, risks, complexity estimate

### Code-Based Graders
```bash
# Check plan has requirements restatement
grep -qi "requirements" plan-output.md && echo "PASS" || echo "FAIL"

# Check plan has implementation phases
grep -qi "phase" plan-output.md && echo "PASS" || echo "FAIL"

# Check plan identifies risks
grep -qi "risk" plan-output.md && echo "PASS" || echo "FAIL"

# Check plan has dependency analysis
grep -qi "depend" plan-output.md && echo "PASS" || echo "FAIL"
```

### Regression Evals
- [ ] Plan generation completes within reasonable tool calls (< 10)
- [ ] Plan references existing project files when relevant
- [ ] Plan does not write code or make file changes
