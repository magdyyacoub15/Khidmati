import re
import time
import sys
from deep_translator import GoogleTranslator

dart_file_path = r'c:\manger3\lib\l10n\app_translations.dart'

# Target languages
targets = ['fr', 'es', 'de', 'it', 'pt', 'nl', 'ru', 'pl', 'sv', 'el', 'uk', 'ro', 'cs', 'hu']

def extract_en_dict():
    with open(dart_file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    start_idx = content.find("'en': {")
    if start_idx == -1:
        print("Could not find 'en' dictionary.", flush=True)
        return {}
        
    start_dict = content.find("{", start_idx)
    open_brackets = 1
    end_dict = -1
    for i in range(start_dict + 1, len(content)):
        if content[i] == '{':
            open_brackets += 1
        elif content[i] == '}':
            open_brackets -= 1
            if open_brackets == 0:
                end_dict = i
                break
                
    dict_str = content[start_dict:end_dict+1]
    
    en_dict = {}
    lines = dict_str.split('\n')
    for line in lines:
        line = line.strip()
        if not line or line.startswith('//'):
            continue
        
        match = re.search(r"'([^']+)'\s*:\s*'([^']+)'|\"([^\"]+)\"\s*:\s*\"([^\"]+)\"|'([^']+)'\s*:\s*\"([^\"]+)\"|\"([^\"]+)\"\s*:\s*'([^']+)'", line)
        if match:
            if match.group(1): k, v = match.group(1), match.group(2)
            elif match.group(3): k, v = match.group(3), match.group(4)
            elif match.group(5): k, v = match.group(5), match.group(6)
            elif match.group(7): k, v = match.group(7), match.group(8)
            else: continue
            
            en_dict[k] = v
            
    return en_dict

def translate_dict(en_dict, target_lang):
    translated = {}
    translator = GoogleTranslator(source='en', target=target_lang)
    
    keys = list(en_dict.keys())
    values = list(en_dict.values())
    
    print(f"\n--- Translating {len(keys)} keys to {target_lang} ---", flush=True)
    
    batch_size = 30
    translated_values = []
    
    for i in range(0, len(values), batch_size):
        batch = values[i:i+batch_size]
        try:
            res = translator.translate_batch(batch)
            translated_values.extend([r if r else v for r, v in zip(res, batch)])
            print(f"✅ Translated {i + len(batch)} / {len(values)} for {target_lang}", flush=True)
        except Exception as e:
            print(f"⚠️ Error batch {i}, falling back to single translation. Error: {e}", flush=True)
            for v in batch:
                try:
                    time.sleep(0.5)
                    res = translator.translate(v)
                    translated_values.append(res if res else v)
                except Exception as ex:
                    print(f"❌ Error on '{v}': {ex}", flush=True)
                    translated_values.append(v)
        time.sleep(2) # Prevent rate limiting
        
    for k, v in zip(keys, translated_values):
        safe_v = str(v).replace("'", "\\'")
        translated[k] = safe_v
        
    return translated

def append_to_dart(translations_map):
    with open(dart_file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    target_idx = content.rfind("};")
    if target_idx == -1:
        print("Could not find end of translations map.", flush=True)
        return
        
    new_dart_code = ""
    for lang, trans_dict in translations_map.items():
        new_dart_code += f"\n    // {lang.upper()} Translations\n"
        new_dart_code += f"    '{lang.split('-')[0]}': {{\n"
        for k, v in trans_dict.items():
            new_dart_code += f"      '{k}': '{v}',\n"
        new_dart_code += "    },\n"
        
    final_content = content[:target_idx] + new_dart_code + content[target_idx:]
    
    with open(dart_file_path, 'w', encoding='utf-8') as f:
        f.write(final_content)
        
    print("\n✅ Translations appended successfully to dart file.", flush=True)

if __name__ == "__main__":
    en_dict = extract_en_dict()
    print(f"Extracted {len(en_dict)} keys from English dictionary.", flush=True)
    
    if len(en_dict) == 0:
        sys.exit(1)
        
    all_translated = {}
    for t in targets:
        all_translated[t] = translate_dict(en_dict, t)
        
    append_to_dart(all_translated)
