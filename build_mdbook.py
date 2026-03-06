import os
import re
import shutil

with open("README.md", "r", encoding="utf-8") as f:
    readme_content = f.readlines()

summary_lines = ["# Summary\n\n[课程简介](README.md)\n\n"]

for line in readme_content:
    line = line.strip()
    if line == "## 📖 阅读建议":
        break
    if line.startswith("### "):
        title = line.replace("### ", "").replace("🚀 ", "").replace("🔐 ", "").replace("🔬 ", "")
        summary_lines.append(f"\n# {title}\n\n")
    elif line.startswith("| Chapter ") or line.startswith("| Example "):
        parts = [p.strip() for p in line.split("|") if p.strip()]
        if len(parts) >= 3 and not parts[0].startswith("章节") and not parts[0].startswith("案例") and not parts[0].startswith("---"):
            ch_num = parts[0]
            link_match = re.search(r'\((.*?)\)', parts[1])
            if link_match:
                link = link_match.group(1).replace("./", "")
                desc = parts[2].split("：")[0].replace("**", "")
                summary_lines.append(f"- [{ch_num}: {desc}]({link})\n")

with open("SUMMARY.md", "w", encoding="utf-8") as f:
    f.writelines(summary_lines)

os.makedirs("src", exist_ok=True)
for file in os.listdir("."):
    if file.endswith(".md") and file != "SUMMARY.md":
        shutil.move(file, os.path.join("src", file))
shutil.move("SUMMARY.md", os.path.join("src", "SUMMARY.md"))

if os.path.exists("code"):
    shutil.move("code", os.path.join("src", "code"))
