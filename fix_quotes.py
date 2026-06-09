with open('c:/manger3/add_profile_translations.py', 'r', encoding='utf-8') as f:
    text = f.read()

lines = text.split('\n')
for i in range(len(lines)):
    if i < 305:
        lines[i] = lines[i].replace("\\\\'", "\\'")

with open('c:/manger3/add_profile_translations.py', 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
