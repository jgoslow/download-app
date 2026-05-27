# Workflow Behavior Notes

## Core insight
A workflow is not defined by the user upfront — it emerges from context. But once it exists, it has an instruction (English-language LLM prompt) that makes it specific and reusable. The instruction is what distinguishes "Create a Jira card" from "Create a Jira card in the TACA project tagged urgent when I say something is blocking."

## What makes a workflow unique
Not the tool actions — those are generic. The **instruction context** attached to the workflow is what makes it specific:
- "When tasks or blockers are mentioned, create a Jira card in the most relevant project"
- "When I mention a meeting, send a brief Slack message to #standup summarizing the key points"
- "Log time for this session based on the topics discussed"

The instruction is fed to Castellum alongside the capture transcript. Castellum decides whether/how to activate the workflow.

## On/off toggle
Workflows can be enabled/disabled. But the enable/disable is secondary — the primary value is the instruction.

## Onboarding
Users shouldn't be expected to define workflows from scratch. Onboarding should:
1. Show a curated set of workflow templates based on connected tools
2. Let users accept, customize (edit the instruction), or skip each
3. Possibly ask a few questions to personalize the defaults

After onboarding, users can create new workflows or edit existing ones conversationally (describe what you want, Basin asks clarifying questions).

## Flow scoping
Each workflow can optionally be scoped to a specific Flow (e.g., "only run this workflow during Morning Kickoff"). Nil = run in any flow. This allows the same tool (e.g., Jira) to behave differently in different flows.

## No automation UI
Workflows are defined in plain English. No flowchart builder, no trigger/condition/action UX. Castellum interprets the instruction. This is the right tradeoff for v1.

## Relationship to tools
- Tools declare what actions they can perform (`outcomes` in tool definition JSON)
- Workflows declare *what to do* in natural language
- Castellum connects them: given a workflow instruction + a capture + connected tools, it builds an execution plan

## Future
- Multi-step workflows (sequence of actions across multiple tools)
- Workflow templates marketplace
- User-contributed workflows
