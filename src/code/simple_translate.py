#!/usr/bin/env python3
"""
Simple file-by-file translator that outputs translation prompts
for Claude to process
"""

import sys
from pathlib import Path

def translate_file(source_path, target_path):
    """Read source file and prepare for translation"""
    with open(source_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Create translation prompt
    prompt = f"""Translate this Chinese markdown file to English.

IMPORTANT GUIDELINES:
- Preserve ALL markdown formatting exactly
- Keep technical terms in English
- Keep code blocks UNCHANGED
- Translate creative ideas accurately
- DO NOT add explanations
- Output ONLY the translated markdown

File: {source_path.name}

Content:
{content}
"""

    print(f"=== TRANSLATING: {source_path.name} ===")
    print(prompt)
    print(f"=== END OF PROMPT ===\n")

    return prompt

def process_directory(zh_dir, en_dir, file_pattern="idea_*.md"):
    """Process all files in a directory"""
    zh_path = Path(zh_dir)
    en_path = Path(en_dir)

    en_path.mkdir(parents=True, exist_ok=True)

    files = sorted(zh_path.glob(file_pattern))
    print(f"Found {len(files)} files to translate in {zh_dir}")

    return files

def main():
    base = "/Users/henryduong/Documents/workspace/eve-bootcamp/src"

    # Process idea directory
    idea_files = process_directory(
        f"{base}/zh/idea",
        f"{base}/en/idea"
    )

    # Process idea_general directory
    idea_general_files = process_directory(
        f"{base}/zh/idea_general",
        f"{base}/en/idea_general"
    )

    print(f"\nTotal files to translate:")
    print(f"  zh/idea: {len(idea_files)}")
    print(f"  zh/idea_general: {len(idea_general_files)}")
    print(f"  Total: {len(idea_files) + len(idea_general_files)}")

    all_files = [(f, base + "/en/idea") for f in idea_files] + \
                [(f, base + "/en/idea_general") for f in idea_general_files]

    return all_files

if __name__ == "__main__":
    files = main()
