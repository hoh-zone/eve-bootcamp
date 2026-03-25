import os
import shutil
import json

base_dir = '/Users/mac/work/eve/book/src/code'
template_dir = '/Users/mac/work/eve/builder-scaffold/dapps'

# The 18 examples
examples = [f"example-{str(i).zfill(2)}" for i in range(1, 19)]

for example in examples:
    target_dir = os.path.join(base_dir, example, 'dapp')
    
    # 1. Copy the template (overwrite if exists)
    if os.path.exists(target_dir):
        shutil.rmtree(target_dir)
        
    shutil.copytree(template_dir, target_dir, ignore=shutil.ignore_patterns('node_modules', 'dist', '.env'))
    
    # 2. Update package.json name to avoid workspace conflicts
    pkg_path = os.path.join(target_dir, 'package.json')
    if os.path.exists(pkg_path):
        with open(pkg_path, 'r') as f:
            pkg_data = json.load(f)
            
        pkg_data['name'] = f"evefrontier-{example}-dapp"
        
        with open(pkg_path, 'w') as f:
            json.dump(pkg_data, f, indent=2)

    # 3. Copy .envsample to .env (devnet uses 0x6 clock usually anyway)
    env_sample = os.path.join(target_dir, '.envsample')
    env_file = os.path.join(target_dir, '.env')
    if os.path.exists(env_sample):
        shutil.copy2(env_sample, env_file)

print(f"✅ Successfully scaffolded {len(examples)} dApp frontends!")
