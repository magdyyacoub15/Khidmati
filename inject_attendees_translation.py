import re
import sys

def main():
    try:
        with open(r"c:\manger3\lib\l10n\app_translations.dart", "r", encoding="utf-8") as f:
            content = f.read()

        translations_to_add = {
            'en': "'attendees': 'Attendees',",
            'ar': "'attendees': 'المخدومين',",
            'es': "'attendees': 'Asistentes',",
            'de': "'attendees': 'Teilnehmer',",
            'it': "'attendees': 'Partecipanti',",
            'pt': "'attendees': 'Participantes',",
            'nl': "'attendees': 'Deelnemers',",
            'ru': "'attendees': 'Участники',",
            'pl': "'attendees': 'Uczestnicy',",
            'sv': "'attendees': 'Deltagare',",
            'el': "'attendees': 'Συμμετέχοντες',",
            'uk': "'attendees': 'Учасники',",
            'ro': "'attendees': 'Participanți',",
            'cs': "'attendees': 'Účastníci',",
            'hu': "'attendees': 'Résztvevők',",
        }

        new_content = content
        for lang_code, attendees_trans in translations_to_add.items():
            # Match the language block start: ` 'ar': { `
            block_pattern = re.compile(r"(\n\s*'%s':\s*\{)" % lang_code)
            match = block_pattern.search(new_content)
            if match:
                start_idx = match.end()
                block_snippet = new_content[start_idx:start_idx+10000]
                if "'attendees':" not in block_snippet and '"attendees":' not in block_snippet:
                    insertion = f"\n      {attendees_trans}"
                    new_content = new_content[:start_idx] + insertion + new_content[start_idx:]
                    print(f"Added {lang_code}")
                else:
                    print(f"Skipped {lang_code}")
        
        with open(r"c:\manger3\lib\l10n\app_translations.dart", "w", encoding="utf-8") as f:
            f.write(new_content)
        print("Done.")
    except Exception as e:
        print(f"Failed: {e}")
        
if __name__ == '__main__':
    main()
