#!/usr/bin/env python3
"""
Script to translate Chinese comments in Move files to English.
Preserves all code syntax, indentation, and comment formatting.
"""

import os
import re
import glob
from pathlib import Path

# Translation dictionary for common terms and phrases found in Move files
TRANSLATIONS = {
    # Common patterns
    "我们的": "Our",
    "我的": "My",
    "任何人都可以": "Anyone can",
    "只有": "Only",
    "拥有特定": "with specific",
    "的角色才能": "characters can",
    "才能": "can",
    "必须": "Must",
    "持有": "hold",
    "成员勋章": "member badge",
    "才能调用": "to call",
    "验证": "Verify",
    "调用者": "caller",
    "是否为": "is",
    "授权": "authorized",
    "赞助者": "sponsor",

    # Technical terms
    "Witness 类型": "Witness type",
    "见证": "witness",
    "证明这个调用是合法绑定的扩展": "prove this call is a legitimately bound extension",
    "使用": "Use",
    "作为": "as",

    # Data structures
    "常量": "Constants",
    "数据结构": "Data Structures",
    "对象": "object",
    "事件": "event",

    # Auction-specific
    "竞价历史记录": "Bid history record",
    "动态字段存储": "dynamic field storage",
    "避免大对象": "avoid large objects",
    "拍卖": "Auction",
    "竞拍": "bidding",
    "拍卖对象": "Auction object",
    "token": "token",
    "所有竞价款暂存于此": "All bid funds are held here in escrow",
    "竞价": "Bid",
    "竞价事件": "Bid event",
    "拍卖결束事件": "Auction ended event",  # Note: 결束 is Korean, should be 结束
    "拍卖结束事件": "Auction ended event",
    "创建拍卖": "Create auction",
    "将竞价款存入托管": "Deposit bid funds into escrow",
    "更新当前最高价": "Update current highest bid",
    "记录竞价历史": "Record bid history",
    "动态字段": "dynamic field",
    "结束拍卖": "End auction",
    "将竞价款转给卖家": "Transfer bid funds to seller",
    "取消拍卖": "Cancel auction",
    "无人出价时卖家可取消": "Seller can cancel when there are no bids",
    "已有人出价则不能取消": "Cannot cancel if someone has already bid",

    # Actions
    "存入物品": "deposit items",
    "开放存款": "open deposits",
    "取出物品": "withdraw items",
    "物品": "item",

    # Full sentence patterns
    "任何人都可以存入物品（开放存款）": "Anyone can deposit items (open deposits)",
    "只有拥有特定 Badge（NFT）的角色才能取出物品": "Only characters with a specific Badge (NFT) can withdraw items",
    "验证调用者是否为授权赞助者": "Verify if the caller is an authorized sponsor",
}

def has_chinese(text):
    """Check if text contains Chinese characters."""
    return bool(re.search(r'[\u4e00-\u9fff]', text))

def translate_text(text):
    """
    Translate Chinese text to English using the translation dictionary.
    Handles partial matches and preserves technical terms.
    """
    if not has_chinese(text):
        return text

    result = text

    # Sort by length (longest first) to handle multi-word phrases before single words
    sorted_translations = sorted(TRANSLATIONS.items(), key=lambda x: len(x[0]), reverse=True)

    for chinese, english in sorted_translations:
        result = result.replace(chinese, english)

    # If there are still Chinese characters, return a note
    if has_chinese(result):
        # Extract remaining Chinese for debugging
        chinese_chars = re.findall(r'[\u4e00-\u9fff]+', result)
        print(f"  Warning: Untranslated Chinese found: {chinese_chars}")
        print(f"    Original: {text}")
        print(f"    Partial translation: {result}")

    return result

def process_line(line):
    """
    Process a single line, translating Chinese in comments while preserving code.
    """
    # Match single-line comments
    single_line_match = re.match(r'^(\s*//\s*)(.*)$', line)
    if single_line_match:
        prefix = single_line_match.group(1)
        comment_text = single_line_match.group(2)
        if has_chinese(comment_text):
            translated = translate_text(comment_text)
            return prefix + translated + '\n'

    return line

def process_file_content(content):
    """
    Process file content, translating all Chinese comments.
    Handles both single-line (//) and multi-line (/* */) comments.
    """
    lines = content.split('\n')
    result_lines = []
    in_multiline_comment = False
    multiline_buffer = []
    multiline_prefix = ""

    for i, line in enumerate(lines):
        # Check for multi-line comment start
        if '/*' in line and '*/' not in line:
            in_multiline_comment = True
            multiline_buffer = [line]
            continue

        # Inside multi-line comment
        if in_multiline_comment:
            multiline_buffer.append(line)
            if '*/' in line:
                # End of multi-line comment
                in_multiline_comment = False
                # Process the entire block
                full_comment = '\n'.join(multiline_buffer)
                if has_chinese(full_comment):
                    translated_block = translate_text(full_comment)
                    result_lines.append(translated_block)
                else:
                    result_lines.append(full_comment)
                multiline_buffer = []
            continue

        # Check for single-line multi-line comment (/* */ on same line)
        multiline_single = re.match(r'^(\s*/\*\s*)(.*)(\s*\*/\s*)$', line)
        if multiline_single:
            prefix = multiline_single.group(1)
            comment_text = multiline_single.group(2)
            suffix = multiline_single.group(3)
            if has_chinese(comment_text):
                translated = translate_text(comment_text)
                result_lines.append(prefix + translated + suffix)
                continue

        # Process single-line comments
        processed_line = process_line(line)
        result_lines.append(processed_line.rstrip('\n'))

    return '\n'.join(result_lines)

def translate_move_files(directory):
    """
    Find and translate all .move files in the given directory.
    """
    move_files = glob.glob(os.path.join(directory, '**/*.move'), recursive=True)

    stats = {
        'total_files': 0,
        'files_with_chinese': 0,
        'files_translated': 0,
        'errors': 0
    }

    samples = []

    for filepath in move_files:
        stats['total_files'] += 1

        try:
            # Read file
            with open(filepath, 'r', encoding='utf-8') as f:
                original_content = f.read()

            # Check if file has Chinese
            if not has_chinese(original_content):
                continue

            stats['files_with_chinese'] += 1
            print(f"\nProcessing: {filepath}")

            # Translate
            translated_content = process_file_content(original_content)

            # Write back
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(translated_content)

            stats['files_translated'] += 1

            # Save sample for first few files
            if len(samples) < 3:
                samples.append({
                    'file': filepath,
                    'original': original_content[:500],
                    'translated': translated_content[:500]
                })

        except Exception as e:
            print(f"Error processing {filepath}: {e}")
            stats['errors'] += 1

    return stats, samples

def main():
    directory = "/Users/henryduong/Documents/workspace/eve-bootcamp/src/code/en/"

    print("=" * 80)
    print("Move File Chinese Comment Translator")
    print("=" * 80)
    print(f"\nScanning directory: {directory}")

    stats, samples = translate_move_files(directory)

    print("\n" + "=" * 80)
    print("TRANSLATION SUMMARY")
    print("=" * 80)
    print(f"Total files scanned: {stats['total_files']}")
    print(f"Files with Chinese comments: {stats['files_with_chinese']}")
    print(f"Files successfully translated: {stats['files_translated']}")
    print(f"Errors: {stats['errors']}")

    if samples:
        print("\n" + "=" * 80)
        print("SAMPLE TRANSLATIONS")
        print("=" * 80)
        for i, sample in enumerate(samples, 1):
            print(f"\nSample {i}: {sample['file']}")
            print("-" * 80)
            print("BEFORE:")
            print(sample['original'])
            print("\nAFTER:")
            print(sample['translated'])
            print("-" * 80)

    print("\n" + "=" * 80)
    print("Translation complete!")
    print("=" * 80)

if __name__ == "__main__":
    main()
