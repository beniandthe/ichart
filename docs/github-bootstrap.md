# iChart — GitHub Bootstrap

Status: Operational helper  
Source of truth: `docs/core-design-document.md`

## Purpose

This document explains how to create and maintain the real GitHub repository for iChart from your local machine.

## Recommended repository layout

```text
ichart/
├── README.md
├── project.yml
├── docs/
│   ├── core-design-document.md
│   ├── developer-mvp-spec.md
│   ├── technical-architecture.md
│   ├── implementation-milestones.md
│   ├── v1-production-deployment.md
│   └── github-bootstrap.md
├── iChart/
│   ├── App/
│   ├── Models/
│   ├── Features/
│   ├── Services/
│   ├── Persistence/
│   └── Shared/
└── .gitignore
```

## Project generation note

This repo can carry a `project.yml` definition as the source-controlled project scaffold.

On a Mac with XcodeGen installed, generate the Xcode project with:

```bash
xcodegen generate
```

That should produce `iChart.xcodeproj` from the checked-in project definition.

## If your local repo is not initialized yet

```bash
git init
git branch -M main
```

## If the repo already exists

Verify that you are using one canonical remote, typically `origin`, and that the tracked branch is `main`.

## Add the files and commit

When the docs, project spec, or scaffold change, run:

```bash
git add .
git commit -m "Align iChart docs and repo structure"
```

## Create the GitHub repository

### Option A — GitHub web UI
1. Create a new empty repository named `ichart` under your account.
2. Do not initialize it with a README, license, or gitignore if your local repo already has commits.
3. Copy the remote URL.

### Option B — GitHub CLI

```bash
gh repo create ichart --private --source=. --remote=origin --push
```

Use `--public` instead of `--private` if you want a public repo immediately.

## If you created the repo in the web UI

SSH:
```bash
git remote add origin git@github.com:<your-handle>/ichart.git
git push -u origin main
```

HTTPS:
```bash
git remote add origin https://github.com/<your-handle>/ichart.git
git push -u origin main
```

## Recommended follow-up GitHub setup

After the first push:
- enable branch protection on `main`
- require pull requests once work starts branching
- add issue labels: `mvp`, `editor`, `recognition`, `layout`, `export`, `rhythm`, `bug`
- optionally create project boards for Milestone 0 through Milestone 7

## Suggested first commits after docs

1. `bootstrap: add Xcode project shell`
2. `feat: add chart domain models and timing model`
3. `feat: add editor shell and sample chart rendering`
4. `feat: add manual chord timing and meter editing`
5. `feat: add PDF export prototype`
6. `feat: add PencilKit capture layer`

## Suggested first issues

- Define chart domain models and chord timing semantics
- Build library screen placeholder
- Build editor shell with systems, measures, and default meter
- Implement object selection and inspector
- Implement manual beat placement and rhythm display for chord events
- Implement PDF export for structured chart objects
- Spike PencilKit stroke capture and candidate recognition
