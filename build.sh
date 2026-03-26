#!/bin/bash
# Build script for EVE Frontier Builder Course (Bilingual)

set -e

echo "🚀 Building EVE Frontier Builder Course..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Build English version (MDBOOK_* overrides match book.en.toml; mdbook has no --config-file in 0.4.x)
echo -e "${BLUE}📚 Building English version...${NC}"
MDBOOK_BOOK__SRC=src/en \
MDBOOK_BOOK__LANGUAGE=en \
MDBOOK_BUILD__BUILD_DIR=book/en \
mdbook build
echo -e "${GREEN}✓ English build complete${NC}"
echo ""

# Build Chinese version
echo -e "${BLUE}📚 Building Chinese version...${NC}"
MDBOOK_BOOK__SRC=src/zh \
MDBOOK_BOOK__LANGUAGE=zh-CN \
MDBOOK_BUILD__BUILD_DIR=book/zh \
mdbook build
echo -e "${GREEN}✓ Chinese build complete${NC}"
echo ""

# Create language selector page
echo -e "${BLUE}📝 Creating language selector...${NC}"
cat > book/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EVE Frontier Builder Course</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255, 255, 255, 0.1);
      backdrop-filter: blur(10px);
      border-radius: 20px;
      box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
      border: 1px solid rgba(255, 255, 255, 0.18);
    }
    h1 {
      font-size: 2.5rem;
      margin-bottom: 10px;
      font-weight: 700;
    }
    .subtitle {
      font-size: 1.1rem;
      margin-bottom: 40px;
      opacity: 0.9;
    }
    .language-selector {
      display: flex;
      gap: 30px;
      justify-content: center;
      flex-wrap: wrap;
    }
    .lang-button {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 10px;
      padding: 30px 50px;
      background: white;
      color: #667eea;
      text-decoration: none;
      border-radius: 15px;
      transition: all 0.3s ease;
      box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
      min-width: 200px;
    }
    .lang-button:hover {
      transform: translateY(-5px);
      box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
    }
    .flag {
      font-size: 4rem;
      line-height: 1;
    }
    .lang-name {
      font-size: 1.5rem;
      font-weight: 600;
    }
    .lang-label {
      font-size: 0.9rem;
      opacity: 0.7;
    }
    footer {
      margin-top: 40px;
      font-size: 0.9rem;
      opacity: 0.8;
    }
    footer a {
      color: white;
      text-decoration: underline;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>EVE Frontier Builder Course</h1>
    <p class="subtitle">Complete Blockchain Development Curriculum</p>

    <div class="language-selector">
      <a href="./en/" class="lang-button">
        <span class="flag">🇬🇧</span>
        <span class="lang-name">English</span>
        <span class="lang-label">36 Chapters + 18 Examples</span>
      </a>

      <a href="./zh/" class="lang-button">
        <span class="flag">🇨🇳</span>
        <span class="lang-name">中文</span>
        <span class="lang-label">36 章节 + 18 个案例</span>
      </a>
    </div>

    <footer>
      <p>Open Source Educational Material</p>
      <p><a href="https://github.com/evefrontier/builder-course">View on GitHub</a></p>
    </footer>
  </div>
</body>
</html>
EOF
echo -e "${GREEN}✓ Language selector created${NC}"
echo ""

echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
echo "📂 Output locations:"
echo "   English: book/en/"
echo "   Chinese: book/zh/"
echo "   Index:   book/index.html"
echo ""
echo "🌐 To preview locally:"
echo "   mdbook serve --port 3000"
echo "   MDBOOK_BOOK__SRC=src/zh MDBOOK_BOOK__LANGUAGE=zh-CN MDBOOK_BUILD__BUILD_DIR=book/zh mdbook serve --port 3001"
