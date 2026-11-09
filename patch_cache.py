import glob, os

files = glob.glob(os.path.expanduser('~/.cache/huggingface/modules/transformers_modules/**/*.py'), recursive=True)
patched_count = 0
for f in files:
    content = open(f, 'r', encoding='utf-8', errors='ignore').read()
    if 'flash_attn' in content:
        content = content.replace('"flash_attn"', '""').replace("'flash_attn'", "''")
        open(f, 'w', encoding='utf-8').write(content)
        print(f'Patched: {f}')
        patched_count += 1
print(f'Successfully patched {patched_count} file(s).')
