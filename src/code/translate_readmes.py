#!/usr/bin/env python3
"""
Translate README.md files
"""

from pathlib import Path
from deep_translator import GoogleTranslator
import time
import re

def translate_text(text):
    """Translate text using Google Translate"""
    try:
        translator = GoogleTranslator(source='zh-CN', target='en')
        # Split into chunks if necessary
        max_chunk_size = 4500
        if len(text) <= max_chunk_size:
            return translator.translate(text)

        # Split by paragraphs
        paragraphs = text.split('\n\n')
        translated_paragraphs = []

        for para in paragraphs:
            if para.strip():
                try:
                    translated = translator.translate(para)
                    translated_paragraphs.append(translated)
                    time.sleep(0.3)
                except:
                    translated_paragraphs.append(para)
            else:
                translated_paragraphs.append(para)

        return '\n\n'.join(translated_paragraphs)
    except Exception as e:
        print(f"Error: {e}")
        return text

def main():
    base = Path("/Users/henryduong/Documents/workspace/eve-bootcamp/src")

    # Translate zh/idea/README.md
    print("Translating zh/idea/README.md...")
    source1 = base / "zh" / "idea" / "README.md"
    target1 = base / "en" / "idea" / "README.md"

    with open(source1, 'r', encoding='utf-8') as f:
        content1 = f.read()

    translated1 = translate_text(content1)

    with open(target1, 'w', encoding='utf-8') as f:
        f.write(translated1)

    print(f"  ✓ Completed: en/idea/README.md")

    time.sleep(1)

    # Translate zh/idea_general/README.md
    print("Translating zh/idea_general/README.md...")
    source2 = base / "zh" / "idea_general" / "README.md"
    target2 = base / "en" / "idea_general" / "README.md"

    with open(source2, 'r', encoding='utf-8') as f:
        content2 = f.read()

    translated2 = translate_text(content2)

    with open(target2, 'w', encoding='utf-8') as f:
        f.write(translated2)

    print(f"  ✓ Completed: en/idea_general/README.md")

    print("\nREADME files translated successfully!")

if __name__ == "__main__":
    main()
