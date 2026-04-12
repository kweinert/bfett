# Agent Context

## Git/GitHub Workflow

### Push + PR
1. Commit changes with descriptive message (conventional commits: `feat:`, `fix:`, `refactor:`, `doc:`)
2. Push using credential helper: `git push -u origin <branch>`
3. Create PR: `gh pr create --base main --head <branch> --title "..." --body "..."`

### Credential Helper
For HTTPS remotes with `gh` auth:
```bash
git config --global credential.helper "!f() { echo password=$(gh auth token); }; f"
```

## Preferred R Packages

- **httr** for API calls 
- **data.table** for importing csv and data manipulation
- **nanoparquet** for handling parquet files

## Code Style
- No comments unless explicitly requested
- Conventional commit messages
- Keep responses concise (1-3 sentences unless detail requested)

## R Coding Best Practices

### Suppress Package Messages
```r
suppressPackageStartupMessages({
  library(jsonlite)
  library(httr)
  library(data.table)
})
```

### Warnings
```r
options(warn = 1)  # Print warnings immediately

warning("message", call. = FALSE)  # Suppress location info
```



