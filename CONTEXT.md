# Project navigation

This context defines repository identity and placement across development machines.

## Language

**Project**:
A Git repository presented as one selectable unit. A Project does not include its Git worktrees.
_Avoid_: Worktree, folder, checkout

**Project identity**:
The key that groups Project locations. It is the normalized `origin` repository address, or the machine and absolute path when the repository has no `origin`.
_Avoid_: Directory name, worktree path

**Project location**:
A primary Git checkout of a Project on one machine. Each location has its own path, current Git HEAD, and clean or dirty working-tree state.
_Avoid_: Project, copy

**Project root**:
A configured directory that `prj` searches for Project locations on one machine. Each Searchable machine may have different Project roots, and root order determines location preference.
_Avoid_: Project, repository

**Code root**:
The `~/Code` directory where `prj` stores durable Project locations.
_Avoid_: Workspace, Sandbox

**Sandbox**:
The `~/Sandbox` directory for temporary experiments. Git repositories in this directory may appear in inventory, but `prj` does not manage their placement.
_Avoid_: Code root

**Searchable machine**:
A development machine whose private host configuration sets `project_search = true`. Its Project locations may appear in cross-machine inventory.
_Avoid_: Workstation, SSH host

**Project inventory**:
The cached set of Project locations discovered by the most recent explicit refresh. Each location retains its last successful refresh time.
_Avoid_: Configuration, registry
