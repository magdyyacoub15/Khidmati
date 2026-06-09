import re

def fix_file(filepath):
    print(f"Processing {filepath}")
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    out_lines = []
    
    current_lang = None
    seen_keys = set()
    skip_mode = False
    
    # Improved regex for language blocks: 'en': { or "en": {
    lang_pattern = re.compile(r"^\s*['\"]([a-z]{2,3})['\"]\s*:\s*\{")
    # Improved regex for keys: 'key': or "key":
    key_pattern = re.compile(r"^\s*['\"]([^'\"]+)['\"]\s*:\s*")
    # End of block: },
    end_pattern = re.compile(r"^\s*\},?")

    for line in lines:
        lang_match = lang_pattern.match(line)
        if lang_match:
            current_lang = lang_match.group(1)
            seen_keys.clear()
            skip_mode = False
            out_lines.append(line)
            print(f"  Entering lang block: {current_lang}")
            continue
            
        if current_lang:
            if end_pattern.match(line):
                current_lang = None
                skip_mode = False
                out_lines.append(line)
                continue
                
            key_match = key_pattern.match(line)
            if key_match:
                key = key_match.group(1)
                if key in seen_keys:
                    print(f"  Removing duplicate key: {key} in {current_lang}")
                    skip_mode = True
                    continue
                else:
                    seen_keys.add(key)
                    skip_mode = False
                    out_lines.append(line)
            else:
                # If we are in skip_mode (because of a duplicate key), 
                # keep skipping lines until we hit a new key or end of block.
                # However, multi-line values should be handled.
                # If it's a comment or empty line, we keep it if not skipping.
                if not skip_mode:
                    out_lines.append(line)
        else:
            out_lines.append(line)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out_lines))

if __name__ == '__main__':
    fix_file('c:/manger3/lib/l10n/app_translations.dart')
    fix_file('c:/manger3/lib/l10n/profile_translations.dart')
    print("Deduplication complete.")
