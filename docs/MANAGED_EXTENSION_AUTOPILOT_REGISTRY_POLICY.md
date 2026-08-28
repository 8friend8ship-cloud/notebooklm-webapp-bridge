# Registry policy

The central managed-extension registry is the source of desired package state. It may be updated by Central Agent when a new app/platform/bridge requirement is proven. Before adding a package, the governor checks existing installed extensions and aliases to avoid duplicates. Existing specialized bridges (NotebookLM, Flow, Front QA, AI Studio, SketchUp) are reused rather than replaced by a broad universal extension.

Publisher/control packages use exact host permissions. New broad host permissions are not added automatically.
