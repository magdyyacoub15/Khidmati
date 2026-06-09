import re

file_path = r'c:\manger3\lib\l10n\app_translations.dart'

translations = {
    'en': {
        'confirm_delete_title': 'Confirm Deletion',
        'confirm_delete_visit_message': "Are you sure you want to delete the visit '%s'?",
        'cancel_button': 'Cancel',
        'delete_button': 'Delete',
    },
    'ar': {
        'confirm_delete_title': 'تأكيد الحذف',
        'confirm_delete_visit_message': "هل أنت متأكد من حذف الزيارة '%s'؟",
        'cancel_button': 'إلغاء',
        'delete_button': 'حذف',
    },
    'fr': {
        'confirm_delete_title': 'Confirmer la suppression',
        'confirm_delete_visit_message': "Êtes-vous sûr de vouloir supprimer la visite '%s'?",
        'cancel_button': 'Annuler',
        'delete_button': 'Supprimer',
    },
    'es': {
        'confirm_delete_title': 'Confirmar eliminación',
        'confirm_delete_visit_message': "¿Está seguro de que desea eliminar la visita '%s'?",
        'cancel_button': 'Cancelar',
        'delete_button': 'Eliminar',
    },
    'de': {
        'confirm_delete_title': 'Löschen bestätigen',
        'confirm_delete_visit_message': "Sind Sie sicher, dass Sie den Besuch '%s' löschen möchten?",
        'cancel_button': 'Abbrechen',
        'delete_button': 'Löschen',
    },
    'it': {
        'confirm_delete_title': 'Conferma eliminazione',
        'confirm_delete_visit_message': "Sei sicuro di voler eliminare la visita '%s'?",
        'cancel_button': 'Annulla',
        'delete_button': 'Elimina',
    },
    'pt': {
        'confirm_delete_title': 'Confirmar exclusão',
        'confirm_delete_visit_message': "Tem certeza que deseja excluir a visita '%s'?",
        'cancel_button': 'Cancelar',
        'delete_button': 'Excluir',
    },
    'nl': {
        'confirm_delete_title': 'Verwijdering bevestigen',
        'confirm_delete_visit_message': "Weet u zeker dat u het bezoek '%s' wilt verwijderen?",
        'cancel_button': 'Annuleren',
        'delete_button': 'Verwijderen',
    },
    'ru': {
        'confirm_delete_title': 'Подтвердить удаление',
        'confirm_delete_visit_message': "Вы уверены, что хотите удалить посещение '%s'?",
        'cancel_button': 'Отмена',
        'delete_button': 'Удалить',
    },
    'pl': {
        'confirm_delete_title': 'Potwierdź usunięcie',
        'confirm_delete_visit_message': "Czy na pewno chcesz usunąć wizytę '%s'?",
        'cancel_button': 'Anuluj',
        'delete_button': 'Usuń',
    },
    'sv': {
        'confirm_delete_title': 'Bekräfta borttagning',
        'confirm_delete_visit_message': "Är du säker på att du vill ta bort besöket '%s'?",
        'cancel_button': 'Avbryt',
        'delete_button': 'Ta bort',
    },
    'el': {
        'confirm_delete_title': 'Επιβεβαίωση Διαγραφής',
        'confirm_delete_visit_message': "Είστε σίγουροι ότι θέλετε να διαγράψετε την επίσκεψη '%s';",
        'cancel_button': 'Ακύρωση',
        'delete_button': 'Διαγραφή',
    },
    'uk': {
        'confirm_delete_title': 'Підтвердити видалення',
        'confirm_delete_visit_message': "Ви впевнені, що хочете видалити візит '%s'?",
        'cancel_button': 'Скасувати',
        'delete_button': 'Видалити',
    },
    'ro': {
        'confirm_delete_title': 'Confirmați ștergerea',
        'confirm_delete_visit_message': "Sunteți sigur că doriți să ștergeți vizita '%s'?",
        'cancel_button': 'Anulare',
        'delete_button': 'Șterge',
    },
    'cs': {
        'confirm_delete_title': 'Potvrdit smazání',
        'confirm_delete_visit_message': "Opravdu chcete smazat návštěvu '%s'?",
        'cancel_button': 'Zrušit',
        'delete_button': 'Smazat',
    },
    'hu': {
        'confirm_delete_title': 'Törlés megerősítése',
        'confirm_delete_visit_message': "Biztosan törölni szeretné a(z) '%s' látogatást?",
        'cancel_button': 'Mégse',
        'delete_button': 'Törlés',
    }
}

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

for lang, trans_dict in translations.items():
    if not trans_dict: continue
    
    pattern = r"('" + lang + r"':\s*\{)"
    match = re.search(pattern, content)
    
    if match:
        insert_pos = match.end()
        # Ensure we don't inject multiple times into the same dictionary
        next_lang_match = re.search(r"'[a-z]{2}':\s*\{", content[insert_pos:])
        end_pos = insert_pos + next_lang_match.start() if next_lang_match else len(content)
        block = content[insert_pos:end_pos]
        
        if "'confirm_delete_title'" not in block:
            injection = "\n"
            for key, val in trans_dict.items():
                val = val.replace("'", "\\'")
                injection += f"      '{key}': '{val}',\n"
            
            content = content[:insert_pos] + injection + content[insert_pos:]
            print(f"Injected deletion translations for {lang}")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Translation injection Done.")
