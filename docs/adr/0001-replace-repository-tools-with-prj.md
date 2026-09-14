# Replace repository tools with prj

We will replace `ghq` and `gwq` with one repository-owned Go CLI named `prj`. One implementation will discover and group repositories, clone into the existing `~/Code/<host>/<owner>/<repository>` layout, query configured machines over SSH, and run `fzf` or Zed at interaction boundaries on macOS, Linux, and Windows. This removes overlapping user interfaces and installations, at the cost of owning the narrow URL parsing and clone-placement behavior that `prj get` needs.
