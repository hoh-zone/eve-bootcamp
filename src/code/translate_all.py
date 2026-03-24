#!/usr/bin/env python3
"""
Translate all Chinese markdown files from zh/idea and zh/idea_general directories
to English and save them in en/idea and en/idea_general directories.
"""

import os
import anthropic
from pathlib import Path

# Initialize Anthropic client
client = anthropic.Anthropic()

def translate_markdown(content: str, source_file: str) -> str:
    """Translate Chinese markdown content to English using Claude."""

    prompt = f"""Translate this Chinese markdown file to English.

IMPORTANT GUIDELINES:
- Preserve ALL markdown formatting exactly (headings, lists, links, etc.)
- Keep technical terms in English
- Keep code blocks UNCHANGED
- Translate creative ideas and descriptions accurately
- Maintain the same structure and style
- DO NOT add any explanations or notes about the translation
- Output ONLY the translated markdown content

Source file: {source_file}

Content to translate:
{content}"""

    message = client.messages.create(
        model="claude-sonnet-4-5-20250929",
        max_tokens=8000,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )

    return message.content[0].text

def process_directory(source_dir: str, target_dir: str) -> int:
    """Process all markdown files in a directory."""
    source_path = Path(source_dir)
    target_path = Path(target_dir)

    # Ensure target directory exists
    target_path.mkdir(parents=True, exist_ok=True)

    # Get all markdown files
    md_files = sorted(source_path.glob("*.md"))

    translated_count = 0

    for md_file in md_files:
        print(f"Translating: {md_file.name}")

        # Read source content
        with open(md_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # Translate
        try:
            translated_content = translate_markdown(content, str(md_file))

            # Write to target
            target_file = target_path / md_file.name
            with open(target_file, 'w', encoding='utf-8') as f:
                f.write(translated_content)

            translated_count += 1
            print(f"  ✓ Completed: {md_file.name} -> {target_file}")
        except Exception as e:
            print(f"  ✗ Error translating {md_file.name}: {e}")

    return translated_count

def main():
    """Main translation process."""
    base_path = "/Users/henryduong/Documents/workspace/eve-bootcamp/src"

    directories = [
        {
            "source": f"{base_path}/zh/idea",
            "target": f"{base_path}/en/idea",
            "name": "idea"
        },
        {
            "source": f"{base_path}/zh/idea_general",
            "target": f"{base_path}/en/idea_general",
            "name": "idea_general"
        }
    ]

    total_translated = 0
    summary = {}

    for dir_info in directories:
        print(f"\n{'='*60}")
        print(f"Processing: {dir_info['name']}")
        print(f"{'='*60}")

        count = process_directory(dir_info['source'], dir_info['target'])
        summary[dir_info['name']] = count
        total_translated += count

        print(f"\nCompleted {dir_info['name']}: {count} files translated")

    print(f"\n{'='*60}")
    print(f"TRANSLATION SUMMARY")
    print(f"{'='*60}")
    for name, count in summary.items():
        print(f"{name}: {count} files")
    print(f"Total: {total_translated} files translated")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
