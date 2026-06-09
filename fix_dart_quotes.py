with open('c:/manger3/lib/l10n/profile_translations.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace any occurrence of \' with \\' which produces an escaped quote in Dart code inside the constant map
text = text.replace("\\'", "\\\\'")

with open('c:/manger3/lib/l10n/profile_translations.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Fixed profile translations darts escape quotes")
