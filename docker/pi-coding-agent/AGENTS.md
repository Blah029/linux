# AGENTS.md

- Pi Coding Agent is running in a Docker container
- Changes outside /workspace will not persist
- Make sure to use available tools

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

## Dependencies

- Download packages using package manager
- Download other dependecies to /opt and use symlinks
- Report all dependency downloads to user
