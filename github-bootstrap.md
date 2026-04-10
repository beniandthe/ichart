# Smart Chart — GitHub Bootstrap

Status: Operational helper  
Source of truth: `docs/core-design-document.md`

## Purpose

This document explains how to create and connect the real GitHub repository for Smart Chart from your local machine.

## Recommended repository layout

```text
smart-chart/
├── README.md
├── docs/
│   ├── core-design-document.md
│   ├── developer-mvp-spec.md
│   ├── technical-architecture.md
│   ├── v1-production-deployment.md
│   └── github-bootstrap.md
├── SmartChart/
│   ├── App/
│   ├── Models/
│   ├── Features/
│   ├── Services/
│   ├── Persistence/
│   └── Shared/
└── .gitignore
```

## If your local repo is not initialized yet

```bash
git init
git branch -M main
```

## Add the files and commit

Copy the repo-ready files into your real local `smart-chart` folder, then run:

```bash
git add .
git commit -m "Add Smart Chart design and planning docs"
```

## Create the GitHub repository

### Option A — GitHub web UI
1. Create a new empty repository named `smart-chart` under your account.
2. Do not initialize it with a README, license, or gitignore if your local repo already has commits.
3. Copy the remote URL.

### Option B — GitHub CLI

```bash
gh repo create smart-chart --private --source=. --remote=origin --push
```

Use `--public` instead of `--private` if you want a public repo immediately.

## If you created the repo in the web UI

SSH:
```bash
git remote add origin git@github.com:beniandthe/smart-chart.git
git push -u origin main
```

HTTPS:
```bash
git remote add origin https://github.com/beniandthe/smart-chart.git
git push -u origin main
```

## Recommended follow-up GitHub setup

After the first push:
- enable branch protection on `main`
- require pull requests once work starts branching
- add issue labels: `mvp`, `editor`, `recognition`, `layout`, `export`, `bug`
- optionally create project boards for Milestone 0 through Milestone 6

## Suggested first commits after docs

1. `bootstrap: add Xcode project shell`
2. `feat: add chart domain models`
3. `feat: add editor shell and sample chart rendering`
4. `feat: add PDF export prototype`
5. `feat: add PencilKit capture layer`

## Suggested first issues

- Define chart domain models
- Build library screen placeholder
- Build editor shell with systems and measures
- Implement object selection and inspector
- Implement PDF export for structured chart objects
- Spike PencilKit stroke capture and candidate recognition
