# Build Documentation - EVE Frontier Builder Course

## Overview

This repository contains a bilingual (English/Chinese) mdBook-based educational course for EVE Frontier blockchain development. The content is organized in a parallel directory structure to support both languages.

## Directory Structure

```
eve-bootcamp/
├── book.en.toml              # English book configuration
├── book.zh.toml              # Chinese book configuration
├── README.md                 # Bilingual root README
├── BUILD.md                  # This file - build instructions
├── src/
│   ├── en/                   # English content
│   │   ├── index.md          # Course homepage
│   │   ├── SUMMARY.md        # Navigation structure
│   │   ├── glossary.md       # Technical glossary
│   │   ├── chapter-00.md     # Prelude (36 chapters total)
│   │   ├── chapter-01.md
│   │   ├── ...
│   │   ├── chapter-35.md
│   │   ├── example-01.md     # Practical examples (18 total)
│   │   ├── ...
│   │   ├── example-18.md
│   │   ├── idea/             # Hackathon ideas (101 files)
│   │   │   ├── README.md
│   │   │   └── idea_001.md → idea_100.md
│   │   └── idea_general/     # General ideas (101 files)
│   │       ├── README.md
│   │       └── idea_001.md → idea_100.md
│   ├── zh/                   # Chinese content (same structure)
│   │   └── [mirror of en/ structure]
│   └── code/                 # Code examples
│       ├── en/               # English-commented code
│       │   ├── chapter-03/
│       │   ├── chapter-04/
│       │   ├── ...
│       │   └── example-18/
│       └── zh/               # Chinese-commented code
│           └── [mirror of en/ structure]
└── book/                     # Build output (generated)
    ├── en/                   # English build
    └── zh/                   # Chinese build
```

## Prerequisites

### Required Software

1. **mdBook** - Static site generator for creating books from Markdown
   ```bash
   # Install via Cargo (Rust package manager)
   cargo install mdbook

   # Or via package managers:
   # macOS
   brew install mdbook

   # Linux
   curl -sSL https://github.com/rust-lang/mdBook/releases/download/v0.4.36/mdbook-v0.4.36-x86_64-unknown-linux-gnu.tar.gz | tar -xz
   ```

2. **Optional: mdBook plugins**
   ```bash
   # For better search functionality
   cargo install mdbook-toc

   # For mermaid diagrams (if used)
   cargo install mdbook-mermaid
   ```

### Verify Installation

```bash
mdbook --version
# Should output: mdbook v0.4.36 or newer
```

## Building the Book

### Build English Version

```bash
# From repository root
mdbook build --config-file book.en.toml

# Output will be in: book/en/
```

### Build Chinese Version

```bash
# From repository root
mdbook build --config-file book.zh.toml

# Output will be in: book/zh/
```

### Build Both Versions

```bash
# Build both languages
mdbook build --config-file book.en.toml && \
mdbook build --config-file book.zh.toml

# Or use a build script (create build.sh):
#!/bin/bash
echo "Building English version..."
mdbook build --config-file book.en.toml
echo "Building Chinese version..."
mdbook build --config-file book.zh.toml
echo "Build complete!"
```

## Development

### Live Preview with Auto-Reload

```bash
# Serve English version (auto-reloads on file changes)
mdbook serve --config-file book.en.toml --port 3000

# Serve Chinese version (on different port)
mdbook serve --config-file book.zh.toml --port 3001

# Open in browser:
# English: http://localhost:3000
# Chinese: http://localhost:3001
```

### Watch for Changes (Build Only)

```bash
# Watch English version
mdbook watch --config-file book.en.toml

# Watch Chinese version
mdbook watch --config-file book.zh.toml
```

## Deployment

### GitHub Pages

Add to `.github/workflows/deploy.yml`:

```yaml
name: Deploy mdBook

on:
  push:
    branches: [ main ]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup mdBook
        uses: peaceiris/actions-mdbook@v1
        with:
          mdbook-version: 'latest'

      - name: Build English version
        run: mdbook build --config-file book.en.toml

      - name: Build Chinese version
        run: mdbook build --config-file book.zh.toml

      - name: Create index redirect
        run: |
          mkdir -p book
          cat > book/index.html << 'EOF'
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>EVE Frontier Builder Course</title>
            <style>
              body { font-family: sans-serif; max-width: 600px; margin: 100px auto; text-align: center; }
              a { display: inline-block; margin: 20px; padding: 20px 40px; background: #3F51B5; color: white; text-decoration: none; border-radius: 4px; }
              a:hover { background: #303F9F; }
            </style>
          </head>
          <body>
            <h1>EVE Frontier Builder Course</h1>
            <p>Choose your language / 选择语言:</p>
            <a href="./en/">🇬🇧 English</a>
            <a href="./zh/">🇨🇳 中文</a>
          </body>
          </html>
          EOF

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./book

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### Static Hosting (Netlify, Vercel, etc.)

1. Build both versions:
   ```bash
   ./build.sh
   ```

2. Upload the `book/` directory to your hosting service

3. Configure custom domains if needed

### Self-Hosted

```bash
# Build both versions
mdbook build --config-file book.en.toml
mdbook build --config-file book.zh.toml

# Serve with any web server
cd book
python3 -m http.server 8080
# Or use nginx, Apache, etc.
```

## File Organization Guidelines

### Adding New Content

#### 1. Add a New Chapter

**English:**
```bash
# Create the file
touch src/en/chapter-36.md

# Edit src/en/SUMMARY.md and add:
# - [Chapter 36: Your Title](./chapter-36.md)
```

**Chinese:**
```bash
# Create the file
touch src/zh/chapter-36.md

# Edit src/zh/SUMMARY.md and add:
# - [第 36 章：你的标题](./chapter-36.md)
```

#### 2. Add a New Example

Follow the same pattern as chapters, using `example-XX.md` naming.

#### 3. Add Code Examples

```bash
# English version with English comments
mkdir -p src/code/en/chapter-36
touch src/code/en/chapter-36/sources/example.move

# Chinese version with Chinese comments
mkdir -p src/code/zh/chapter-36
touch src/code/zh/chapter-36/sources/example.move
```

### Maintaining Translations

When updating content:

1. **Update English first** in `src/en/`
2. **Update Chinese** in `src/zh/` to match
3. **Update code examples** in both `src/code/en/` and `src/code/zh/`
4. **Rebuild both versions** to verify

## Configuration Files

### book.en.toml

```toml
[book]
authors = ["EVE Frontier Builders"]
language = "en"
src = "src/en"
title = "EVE Frontier Builder Course"

[output.html]
git-repository-url = "https://github.com/evefrontier/builder-course"
edit-url-template = "https://github.com/evefrontier/builder-course/edit/main/{path}"
mathjax-support = true
```

### book.zh.toml

```toml
[book]
authors = ["EVE Frontier Builders"]
language = "zh-CN"
src = "src/zh"
title = "EVE Frontier Builder Course"

[output.html]
git-repository-url = "https://github.com/evefrontier/builder-course"
edit-url-template = "https://github.com/evefrontier/builder-course/edit/main/{path}"
mathjax-support = true
```

## Troubleshooting

### Common Issues

**Issue: `mdbook: command not found`**
```bash
# Install mdbook
cargo install mdbook
```

**Issue: Build fails with "file not found"**
```bash
# Check that src/en/ or src/zh/ exists
ls src/en/SUMMARY.md
ls src/zh/SUMMARY.md

# Verify config points to correct source
cat book.en.toml | grep src
cat book.zh.toml | grep src
```

**Issue: Changes not appearing**
```bash
# Clear previous builds
rm -rf book/

# Rebuild
mdbook build --config-file book.en.toml
```

**Issue: Port already in use**
```bash
# Use different port
mdbook serve --config-file book.en.toml --port 4000
```

## Performance Tips

### Speed Up Builds

1. **Build only what changed**: mdBook automatically detects changes
2. **Parallel builds**: Build EN and ZH in parallel
   ```bash
   mdbook build --config-file book.en.toml & \
   mdbook build --config-file book.zh.toml & \
   wait
   ```

### Optimize for CI/CD

```yaml
# Cache mdBook installation
- uses: actions/cache@v3
  with:
    path: |
      ~/.cargo/bin/mdbook
    key: mdbook-${{ runner.os }}
```

## Statistics

- **Total Markdown Files**: 256 per language (512 total)
  - Core docs: 3 (index, SUMMARY, glossary)
  - Chapters: 36 (chapter-00 through chapter-35)
  - Examples: 18 (example-01 through example-18)
  - Ideas: 202 (101 in idea/, 101 in idea_general/)

- **Move Code Files**: 386 files per language (772 total)
- **Supported Languages**: 2 (English, Chinese)

## Support

For issues or questions:
- Check the [mdBook Documentation](https://rust-lang.github.io/mdBook/)
- Review this BUILD.md file
- Check [EVE Frontier Discord](https://discord.com/invite/evefrontier)

## License

See repository LICENSE file for details.
