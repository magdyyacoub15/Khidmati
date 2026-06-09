import re
import os

file_path = r'c:\manger3\lib\l10n\app_translations.dart'
backup_path = file_path + '.bak'

if not os.path.exists(backup_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        with open(backup_path, 'w', encoding='utf-8') as b:
            b.write(f.read())

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _translations map content
match = re.search(r'static const Map<String, Map<String, String>> _translations = \{(.*)\};', content, re.DOTALL)
if not match:
    print("Could not find _translations map")
    exit(1)

translations_body = match.group(1)

# Find each language block
# Pattern matches 'lang': { ... }
lang_pattern = re.compile(r"(\s+)'([a-z]{2})':\s*\{(.*?)\},", re.DOTALL)

def deduplicate_block(match):
    indent = match.group(1)
    lang = match.group(2)
    inner_content = match.group(3)
    
    # Simple regex for 'key': 'value', or 'key': "value", or 'key': '''value''', or 'key': """value""",
    # This might be tricky with multiline. 
    # Let's try to split by lines and handle common patterns.
    
    lines = inner_content.split('\n')
    kv_pairs = {}
    other_lines = []
    
    # We want to preserve comments if possible, but duplicates are the priority.
    # Standard format seems to be: 'key': 'value',
    
    for line in lines:
        kv_match = re.match(r"^\s+'([^']+)':\s*(.*?),?$", line)
        if kv_match:
            key = kv_match.group(1)
            val = kv_match.group(2)
            kv_pairs[key] = line.strip()
        else:
            if line.strip():
                other_lines.append(line)

    # Reconstruct
    new_lines = []
    # Try to keep original order of keys (first seen)
    seen_keys = []
    for line in lines:
        kv_match = re.match(r"^\s+'([^']+)':\s*(.*?),?$", line)
        if kv_match:
            key = kv_match.group(1)
            if key not in seen_keys:
                new_lines.append("      " + kv_pairs[key])
                seen_keys.append(key)
        else:
            if line.strip() or not new_lines or new_lines[-1].strip():
                new_lines.append(line)
    
    # Filter out empty lines at start/end
    while new_lines and not new_lines[0].strip(): new_lines.pop(0)
    while new_lines and not new_lines[-1].strip(): new_lines.pop(-1)

    return f"{indent}'{lang}': {{\n" + "\n".join(new_lines) + f"\n{indent}}},"

new_translations_body = lang_pattern.sub(deduplicate_block, translations_body)

# Replace in original content
new_content = content.replace(translations_body, new_translations_body)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Deduplication complete.")
