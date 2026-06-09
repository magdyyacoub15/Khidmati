import re

def fix_translations():
    with open('c:/manger3/lib/l10n/app_translations.dart', 'r', encoding='utf-8') as f:
        text = f.read()

    # The block of duplicate translations starts with:
    # 'global_broadcast_title': 'Notification Globale 📢',
    # We will find the duplicate insertions and remove them.
    # We can use regex to find blocks of translations added by the previous script and format them correctly if needed.
    
    # Actually, it looks like the `add_profile_translations.py` script simply appended the new keys 
    # to the end of the existing language map, but didn't check if they already existed, or injected them multiple times.
    
    # Let's fix the file by loading it, replacing all `\'` with `\\'` where appropriate, 
    # and removing any duplicate keys from within the maps.
    
    # Since dart map parsing is complex, let's just do text replacements for the specific duplicates.
    # We'll use a simpler script to fix dart quotes first.
    
    text = text.replace("\\'", "\\\\'")
    
    with open('c:/manger3/lib/l10n/app_translations.dart', 'w', encoding='utf-8') as f:
        f.write(text)
        
if __name__ == '__main__':
    fix_translations()
