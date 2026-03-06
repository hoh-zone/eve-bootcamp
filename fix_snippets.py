import os
import glob
import re

def fix_snippets():
    code_dir = '/Users/mac/work/eve/book/code'
    snippet_files = glob.glob(f'{code_dir}/**/snippets/*.move', recursive=True)
    
    for filepath in snippet_files:
        with open(filepath, 'r') as f:
            content = f.read()
            
        if 'module ' not in content:
            # Extract chapter number and snippet name
            match = re.search(r'chapter-(\d+)/snippets/(snippet_\d+)\.move', filepath)
            if match:
                ch = match.group(1)
                snippet = match.group(2)
                module_decl = f"module chapter_{ch}::{snippet};\n\n"
                
                # Prepend to file
                new_content = module_decl + content
                with open(filepath, 'w') as f:
                    f.write(new_content)
                print(f"Fixed {filepath}")

if __name__ == '__main__':
    fix_snippets()
