#!/usr/bin/env python3
"""
Production translation script using deep-translator
Translates all Chinese markdown files to English
"""

from pathlib import Path
from deep_translator import GoogleTranslator
import time
import re

def preserve_markdown_elements(text):
    """Extract markdown elements to preserve them during translation"""
    # Store code blocks
    code_blocks = []
    def replace_code(match):
        code_blocks.append(match.group(0))
        return f"___CODE_BLOCK_{len(code_blocks)-1}___"

    # Preserve code blocks
    text = re.sub(r'```[\s\S]*?```', replace_code, text)

    # Preserve inline code
    inline_codes = []
    def replace_inline_code(match):
        inline_codes.append(match.group(0))
        return f"___INLINE_CODE_{len(inline_codes)-1}___"

    text = re.sub(r'`[^`]+`', replace_inline_code, text)

    return text, code_blocks, inline_codes

def restore_markdown_elements(text, code_blocks, inline_codes):
    """Restore preserved markdown elements"""
    # Restore code blocks
    for i, block in enumerate(code_blocks):
        text = text.replace(f"___CODE_BLOCK_{i}___", block)

    # Restore inline code
    for i, code in enumerate(inline_codes):
        text = text.replace(f"___INLINE_CODE_{i}___", code)

    return text

def translate_markdown_file(content, filename):
    """Translate markdown content while preserving formatting"""
    try:
        # Preserve markdown elements
        preserved_text, code_blocks, inline_codes = preserve_markdown_elements(content)

        # Split into chunks (Google Translate has a 5000 char limit)
        max_chunk_size = 4500
        lines = preserved_text.split('\n')

        translated_lines = []
        current_chunk = []
        current_size = 0

        translator = GoogleTranslator(source='zh-CN', target='en')

        for line in lines:
            line_size = len(line)

            # If adding this line would exceed limit, translate current chunk
            if current_size + line_size > max_chunk_size and current_chunk:
                chunk_text = '\n'.join(current_chunk)
                try:
                    translated_chunk = translator.translate(chunk_text)
                    translated_lines.append(translated_chunk)
                    time.sleep(0.5)  # Rate limiting
                except Exception as e:
                    print(f"  Warning: Translation error, using original: {e}")
                    translated_lines.append(chunk_text)

                current_chunk = [line]
                current_size = line_size
            else:
                current_chunk.append(line)
                current_size += line_size + 1  # +1 for newline

        # Translate remaining chunk
        if current_chunk:
            chunk_text = '\n'.join(current_chunk)
            try:
                translated_chunk = translator.translate(chunk_text)
                translated_lines.append(translated_chunk)
            except Exception as e:
                print(f"  Warning: Translation error, using original: {e}")
                translated_lines.append(chunk_text)

        # Combine translated text
        translated_text = '\n'.join(translated_lines)

        # Restore markdown elements
        translated_text = restore_markdown_elements(translated_text, code_blocks, inline_codes)

        return translated_text

    except Exception as e:
        print(f"  Error translating {filename}: {e}")
        return content  # Return original if translation fails

def process_file(source_path, target_path):
    """Process a single markdown file"""
    try:
        print(f"Translating: {source_path.name}")

        # Read source file
        with open(source_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Translate
        translated_content = translate_markdown_file(content, source_path.name)

        # Write target file
        target_path.parent.mkdir(parents=True, exist_ok=True)
        with open(target_path, 'w', encoding='utf-8') as f:
            f.write(translated_content)

        print(f"  ✓ Completed: {target_path.name}")
        return True

    except Exception as e:
        print(f"  ✗ Error processing {source_path.name}: {e}")
        return False

def main():
    """Main translation process"""
    base = Path("/Users/henryduong/Documents/workspace/eve-bootcamp/src")

    directories = [
        ("zh/idea", "en/idea"),
        ("zh/idea_general", "en/idea_general")
    ]

    total = 0
    success = 0
    failed = 0

    print("="*60)
    print("EVE Bootcamp Translation Script")
    print("="*60)
    print()

    for zh_dir, en_dir in directories:
        zh_path = base / zh_dir
        en_path = base / en_dir

        files = sorted(zh_path.glob("idea_*.md"))

        print(f"\n{'='*60}")
        print(f"Processing: {zh_dir}")
        print(f"Files: {len(files)}")
        print(f"{'='*60}\n")

        for i, source_file in enumerate(files, 1):
            target_file = en_path / source_file.name
            print(f"[{i}/{len(files)}] ", end='')

            total += 1
            if process_file(source_file, target_file):
                success += 1
            else:
                failed += 1

            # Rate limiting between files
            if i < len(files):
                time.sleep(1)

    print(f"\n{'='*60}")
    print(f"TRANSLATION SUMMARY")
    print(f"{'='*60}")
    print(f"Total files: {total}")
    print(f"Successfully translated: {success}")
    print(f"Failed: {failed}")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
