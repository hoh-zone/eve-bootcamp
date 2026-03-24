#!/usr/bin/env python3
"""
Translate Chinese markdown files to English
This script reads files, generates translation prompts, and writes to a batch file
"""

import os
from pathlib import Path

def generate_translation_requests():
    """Generate a list of all files to translate"""
    base_path = "/Users/henryduong/Documents/workspace/eve-bootcamp/src"

    directories = [
        ("zh/idea", "en/idea"),
        ("zh/idea_general", "en/idea_general")
    ]

    files_to_translate = []

    for zh_dir, en_dir in directories:
        zh_path = Path(base_path) / zh_dir
        en_path = Path(base_path) / en_dir

        # Ensure target directory exists
        en_path.mkdir(parents=True, exist_ok=True)

        # Get all markdown files
        md_files = sorted(zh_path.glob("*.md"))

        for md_file in md_files:
            source = str(md_file)
            target = str(en_path / md_file.name)
            files_to_translate.append((source, target, zh_dir))

    return files_to_translate

def main():
    files = generate_translation_requests()
    print(f"Total files to translate: {len(files)}")

    # Group by directory
    idea_files = [f for f in files if "idea/" in f[2] and "general" not in f[2]]
    idea_general_files = [f for f in files if "idea_general" in f[2]]

    print(f"\nzh/idea/: {len(idea_files)} files")
    print(f"zh/idea_general/: {len(idea_general_files)} files")

    # Write file list for reference
    with open("/Users/henryduong/Documents/workspace/eve-bootcamp/src/code/translation_list.txt", "w") as f:
        f.write("=== zh/idea/ ===\n")
        for source, target, _ in idea_files:
            f.write(f"{os.path.basename(source)}\n")
        f.write(f"\n=== zh/idea_general/ ===\n")
        for source, target, _ in idea_general_files:
            f.write(f"{os.path.basename(source)}\n")

    print("\nFile list written to translation_list.txt")
    return files

if __name__ == "__main__":
    files = main()
