import json
import re

file_path = 'c:/manger3/lib/l10n/app_translations.dart'
json_path = 'c:/manger3/insights.json'

with open(json_path, 'r', encoding='utf-8') as f:
    translations = json.load(f)

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

for lang, trans_dict in translations.items():
    if not trans_dict: continue
    
    # We find the start of the language dictionary
    pattern = r"('" + lang + r"':\s*\{)"
    match = re.search(pattern, content)
    
    if match:
        insert_pos = match.end()
        # Create the string to inject
        injection = "\n"
        for key, val in trans_dict.items():
            # escape single quotes in value
            val = val.replace("'", "\\'")
            injection += f"      '{key}': '{val}',\n"
        
        # Inject right after the brace
        content = content[:insert_pos] + injection + content[insert_pos:]
        print(f"Injected translations for {lang}")
    else:
        print(f"Could not find dictionary for {lang}")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done.")
