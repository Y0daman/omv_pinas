---
name: use-agent-skills
description: Use and maintain the Agent Skills system in this repository. Activate when working with skills, creating new skills, refining descriptions, or restructuring agent workflows.
---

# Use Agent Skills

Use this skill when the task is about creating, editing, validating, or improving skills in this repository.

## Steps

1. Follow the spec in `https://agentskills.io/specification`.
2. Create skills under `.agents/skills/<skill-name>/SKILL.md`.
3. Ensure frontmatter is valid:
   - `name` equals folder name
   - lowercase letters, numbers, hyphens only
   - clear `description` with what + when
4. Keep `SKILL.md` focused; move long details to `references/`.
5. Prefer one coherent unit of work per skill.
6. For reusable multi-step runbooks, create `wf-` prefixed workflow skills.

## Quality checklist

- Skill has concrete defaults, not a long menu of options.
- Skill includes validation or "definition of done".
- Skill contains project-specific gotchas when relevant.
- Skill description has activation keywords likely to appear in real prompts.

## References

- Specification: https://agentskills.io/specification
- What are skills: https://agentskills.io/what-are-skills
- Quickstart: https://agentskills.io/skill-creation/quickstart
- Best practices: https://agentskills.io/skill-creation/best-practices
