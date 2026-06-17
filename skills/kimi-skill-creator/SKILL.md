---
name: kimi-skill-creator
description: Guide for creating new Kimi Code CLI skills based on the official documentation
type: prompt
whenToUse: When the user asks me to create, write, scaffold, or generate a new Kimi Code CLI skill
arguments:
  - name
  - scope
---

You are helping the user create a new Kimi Code CLI Skill. Follow the steps below and consult the official reference documentation at `${KIMI_SKILL_DIR}/references/skills-docs.md` when needed.

## What is a Kimi Code CLI Skill?

A Skill is a Markdown document with optional YAML frontmatter that adds specialized knowledge or a repeatable workflow to Kimi Code CLI. It can be invoked manually with `/skill:<name>` or automatically by the model based on its `description` and `whenToUse` fields.

## Step-by-step creation guide

1. **Choose the skill form**
   - **Directory form (recommended)**: create a folder named after the skill and place `SKILL.md` inside it. Put supporting files (references, scripts, templates) in the same folder.
   - **Flat form**: create a single `<skill-name>.md` file; the filename becomes the skill name.

2. **Choose the location by scope** (more specific scopes take priority: Project > User > Extra > Built-in)
   - **Project**: `.kimi-code/skills/` or `.agents/skills/` in the project root.
   - **User**: `$KIMI_CODE_HOME/skills/` (default `~/.kimi-code/skills/`) or `~/.agents/skills/`.
   - **Extra**: directories listed in `extra_skill_dirs` in `config.toml`.
   - **Built-in**: distributed with Kimi Code CLI; do not create these manually.

3. **Write the YAML frontmatter in `SKILL.md`**
   - Required for directory-form `SKILL.md`:
     - `name`: the skill identifier.
     - `description`: one-line summary the model uses to decide when to invoke the skill.
   - Optional fields:
     - `type`: `prompt` (default) or `flow` (manual-only).
     - `whenToUse`: explicit trigger conditions.
     - `disableModelInvocation`: set to `true` to prevent automatic invocation.
     - `arguments`: list of named parameters, e.g. `arguments: [target, mode]`. Reference them in the body as `$target`, `$mode`.

4. **Write the Markdown body**
   - Explain the workflow, constraints, examples, and references.
   - Keep instructions concise and actionable for the model.
   - Use placeholders correctly:
     - `$ARGUMENTS`: raw argument string passed at invocation.
     - `$0`, `$1`, ... or `$ARGUMENTS[0]`, `$ARGUMENTS[1]`: positional arguments.
     - `$<name>`: named argument declared in frontmatter.
     - `${KIMI_SKILL_DIR}`: directory containing the current skill file.

5. **Add reference material**
   - Place reference files in the same directory (e.g. `${KIMI_SKILL_DIR}/references/skills-docs.md`).
   - Include links to authoritative external documentation so the model can verify details.

6. **Create the files on disk and verify**
   - Use the `Write` tool to create or overwrite files.
   - Read the created files back to confirm the frontmatter and body are correct.

## Important rules

- In directory-form `SKILL.md`, both `name` and `description` are required. Omitting either causes parsing to fail.
- Prefer directory form when the skill needs supporting files.
- Do not create or modify Built-in skills.
- Keep the skill body focused on the single responsibility of creating Kimi Code CLI skills.

## References

- `${KIMI_SKILL_DIR}/references/skills-docs.md`
