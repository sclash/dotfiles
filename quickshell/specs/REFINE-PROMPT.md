# Main goal

We want to refine all the specs

# Feasibility assessment

- Is it doable?
- Do we need external dependencies?
- What's the cost in terms of CPU and memory usage?

# Agentic Setup

- Ideally I would like to have multiple agents communicating with each other 
in herdr using the `/herdr` skill. 

# Agent team

- ***Orchestrator :*** Each `builder` should report to the `orchestrator`
the `orchestrator` trigger the `tester`, if the `tester` feedback is positive
the `builder` job is done, otherwise the `orchestrator` makes the builder fix it.
- ***Builders :*** Each `builder` has a separate task. One `builder` for the `Bar`
One each for all the launchers. I think it is self explanatory that some of the activity
done through the launchers should be reflected in the bar. Think about connecting to Wifi 
or to a bluetooth device.
- ***Tester :*** Upon being prompted from the `orchestrator` it checks that the `builder`
work has been done correctly.


# GIT commits

commit with a meaningful message every time a `builder` work has been approved.
