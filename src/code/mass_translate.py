#!/usr/bin/env python3
"""
Mass translation script - processes all files by creating a manifest
that Claude can then process systematically
"""

from pathlib import Path
import json

def create_translation_manifest():
    """Create a JSON manifest of all files to translate"""
    base = Path("/Users/henryduong/Documents/workspace/eve-bootcamp/src")

    manifest = {
        "zh/idea": [],
        "zh/idea_general": []
    }

    # Process zh/idea
    idea_dir = base / "zh" / "idea"
    idea_files = sorted(idea_dir.glob("idea_*.md"))
    for f in idea_files:
        manifest["zh/idea"].append({
            "source": str(f),
            "target": str(base / "en" / "idea" / f.name),
            "name": f.name
        })

    # Process zh/idea_general
    general_dir = base / "zh" / "idea_general"
    general_files = sorted(general_dir.glob("idea_*.md"))
    for f in general_files:
        manifest["zh/idea_general"].append({
            "source": str(f),
            "target": str(base / "en" / "idea_general" / f.name),
            "name": f.name
        })

    # Save manifest
    manifest_file = base / "code" / "translation_manifest.json"
    with open(manifest_file, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    # Print summary
    idea_count = len(manifest["zh/idea"])
    general_count = len(manifest["zh/idea_general"])
    total = idea_count + general_count

    print(f"Translation Manifest Created:")
    print(f"  zh/idea: {idea_count} files")
    print(f"  zh/idea_general: {general_count} files")
    print(f"  Total: {total} files")
    print(f"\nManifest saved to: {manifest_file}")

    return manifest

if __name__ == "__main__":
    manifest = create_translation_manifest()
