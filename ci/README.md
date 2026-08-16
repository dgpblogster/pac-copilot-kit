# CI recipes

Runnable versions of the pipelines sketched in the design doc, one per platform. Both do the same four things: install `pac`, install the kit, dry-run the deployment, deploy. Adjust the solution name, publisher prefix, and source path to your agent, and wire up the variables each file documents at the top.

| Recipe | Platform |
|---|---|
| [github-actions/deploy-agent.yml](github-actions/deploy-agent.yml) | GitHub Actions |
| [azure-pipelines/deploy-agent.yml](azure-pipelines/deploy-agent.yml) | Azure DevOps (Power Platform Build Tools for the pac install) |

**Azure DevOps prerequisite:** the [Microsoft Power Platform Build Tools](https://marketplace.visualstudio.com/items?itemName=microsoft-IsvExpTools.PowerPlatform-BuildTools) extension must be installed in your organization, but only its Tool Installer task is used; it puts `pac` on the build agent. The who-am-i task and the service connection it usually brings along are deliberately absent, because the kit's CI mode authenticates from the `PCK_SPN_*` variables and manages its own temporary `pac` profile. On GitHub the equivalent is `microsoft/powerplatform-actions/actions-install`.

## What makes these short

The kit's CI mode does the work that usually bloats these files. When `PCK_SPN_TENANT`, `PCK_SPN_APP_ID`, and `PCK_SPN_SECRET` are all present, every cmdlet authenticates as the service principal, and `Invoke-PckCopilotPipeline` creates a temporary `pac` auth profile for the run and deletes it on exit, success or failure. So there is no who-am-i task, no profile management, and no way for the run to inherit a drifted profile from the build agent, because it never uses one.

The dry-run step is not decoration. It runs every preflight check and the offline workspace lint with nothing mutated, so a misconfigured pipeline fails in the plan step with a typed exit code instead of failing halfway through a deployment.

## Reading a failure

The kit's exit codes are the diagnostic contract: **10 through 19** mean a preflight check refused (the environment or inputs are misconfigured; the log names exactly which condition, fix that and only that), **20** means a known-broken platform route (the message names the working alternatives), **1** is an ordinary operational failure. A refusal will fail the step; that is the design working, not the pipeline flaking.

## Until the PowerShell Gallery publish

`Install-Module PacCopilotKit` works once the module is published. Before that, replace the install step with a clone-and-import:

```yaml
- name: Install PacCopilotKit (pre-release, from source)
  shell: pwsh
  run: |
    git clone --depth 1 https://github.com/dgpblogster/pac-copilot-kit.git $env:RUNNER_TEMP/pck
    Import-Module $env:RUNNER_TEMP/pck/src/PacCopilotKit/PacCopilotKit.psd1
```

(Azure DevOps: same idea, clone into `$(Agent.TempDirectory)` and import from there. Note the import then has to happen in every later script step, since each step is a fresh shell; with `Install-Module`, `Import-Module PacCopilotKit` resolves anywhere.)

**Honesty note:** these recipes are authored against the live-proven pipeline cmdlet, but they have not themselves run end to end in hosted CI, because that requires the Gallery publish and a service principal. First post-publish run gets recorded here, and anything it corrects gets corrected loudly.
