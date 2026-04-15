# Agent Skills

This repository uses the Agent Skills specification: https://agentskills.io/specification

## Structure

```text
.agents/
└── skills/
    ├── <skill-name>/
    │   ├── SKILL.md
    │   ├── references/
    │   ├── scripts/
    │   └── assets/
    └── ...
```

## Principles we follow

- One skill = one directory with `SKILL.md` + YAML frontmatter.
- `name` in frontmatter matches the exact directory name.
- `description` states what the skill does and when to activate it.
- Keep core instructions in `SKILL.md`; move details to `references/`.
- Model reusable workflows as dedicated skills with a `wf-` prefix.

## Validation (optional)

If you install the reference library, you can validate a skill:

```bash
skills-ref validate .agents/skills/<skill-name>
```
