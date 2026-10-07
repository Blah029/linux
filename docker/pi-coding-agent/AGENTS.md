# AGENTS.md

## Environment

- Pi Coding Agent is running in a Docker container
- Changes outside /workspace will not persist
- Report any environment changes and provide equivalent dockerfile commands
- Leave working tree unstaged and uncommitted
- Use available tools

## Tone

- Exact, consistent terms
- No idioms

## Read-only mode

- /workspace is read-only
- Lay out a plan to achieve user's objective

## Write mode

- /workspace is writeable
- Carry out the plan

## Mounts

- -v "~/.pi/agent:/root/.pi/agent"
- -v "~/Documents/github:/mnt/github:ro"
- -v "~/applications:/mnt/applications:ro"

