import re
import os

file_path = r'c:\manger3\lib\l10n\app_translations.dart'

translations = {
    'en': {
        'confirm_leave_group_title': 'Leave Group',
        'confirm_leave_group_message': 'Are you sure you want to leave this group? You will lose access to its data until you join again.',
        'leave_group_btn': 'Leave',
        'cannot_leave_active_group': 'Cannot leave the currently active group. Switch to another group first.',
        'leave_group_error': 'Error leaving group: %s',
    },
    'ar': {
        'confirm_leave_group_title': 'مغادرة المجموعة',
        'confirm_leave_group_message': 'هل أنت متأكد أنك تريد مغادرة هذه المجموعة؟ لن تتمكن من رؤية بياناتها مجدداً إلا بطلب انضمام جديد.',
        'leave_group_btn': 'مغادرة',
        'cannot_leave_active_group': 'لا يمكن مغادرة المجموعة النشطة حالياً. قم بالتبديل إلى مجموعة أخرى أولاً.',
        'leave_group_error': 'خطأ أثناء مغادرة المجموعة: %s',
    },
    'fr': {
        'confirm_leave_group_title': 'Quitter le groupe',
        'confirm_leave_group_message': 'Êtes-vous sûr de vouloir quitter ce groupe ? Vous perdrez l\'accès à ses données.',
        'leave_group_btn': 'Quitter',
        'cannot_leave_active_group': 'Impossible de quitter le groupe actif.',
        'leave_group_error': 'Erreur : %s',
    },
    'es': {
        'confirm_leave_group_title': 'Salir del grupo',
        'confirm_leave_group_message': '¿Está seguro de que desea salir de este grupo?',
        'leave_group_btn': 'Salir',
        'cannot_leave_active_group': 'No se puede salir del grupo activo.',
        'leave_group_error': 'Error: %s',
    },
    'de': {
        'confirm_leave_group_title': 'Gruppe verlassen',
        'confirm_leave_group_message': 'Sind Sie sicher, dass Sie diese Gruppe verlassen möchten?',
        'leave_group_btn': 'Verlassen',
        'cannot_leave_active_group': 'Aktive Gruppe kann nicht verlassen werden.',
        'leave_group_error': 'Fehler: %s',
    },
    'it': {
        'confirm_leave_group_title': 'Lascia il gruppo',
        'confirm_leave_group_message': 'Sei sicuro di voler lasciare questo gruppo?',
        'leave_group_btn': 'Lascia',
        'cannot_leave_active_group': 'Impossibile lasciare il gruppo attivo.',
        'leave_group_error': 'Errore: %s',
    },
    'pt': {
        'confirm_leave_group_title': 'Sair do grupo',
        'confirm_leave_group_message': 'Tem certeza que deseja sair deste grupo?',
        'leave_group_btn': 'Sair',
        'cannot_leave_active_group': 'Não é possível sair do grupo ativo.',
        'leave_group_error': 'Erro: %s',
    },
    'nl': {
        'confirm_leave_group_title': 'Groep verlaten',
        'confirm_leave_group_message': 'Weet u zeker dat u deze groep wilt verlaten?',
        'leave_group_btn': 'Verlaten',
        'cannot_leave_active_group': 'Kan actieve groep niet verlaten.',
        'leave_group_error': 'Fout: %s',
    },
    'ru': {
        'confirm_leave_group_title': 'Выйти из группы',
        'confirm_leave_group_message': 'Вы уверены, что хотите выйти из этой группы?',
        'leave_group_btn': 'Выйти',
        'cannot_leave_active_group': 'Нельзя выйти из активной группы.',
        'leave_group_error': 'Ошибка: %s',
    },
    'pl': {
        'confirm_leave_group_title': 'Opuść grupę',
        'confirm_leave_group_message': 'Czy na pewno chcesz opuścić tę grupę?',
        'leave_group_btn': 'Opuść',
        'cannot_leave_active_group': 'Nie można opuścić aktywnej grupy.',
        'leave_group_error': 'Błąd: %s',
    },
    'sv': {
        'confirm_leave_group_title': 'Lämna grupp',
        'confirm_leave_group_message': 'Är du säker på att du vill lämna den här gruppen?',
        'leave_group_btn': 'Lämna',
        'cannot_leave_active_group': 'Kan inte lämna den aktiva gruppen.',
        'leave_group_error': 'Fel: %s',
    },
    'el': {
        'confirm_leave_group_title': 'Αποχώρηση από την ομάδα',
        'confirm_leave_group_message': 'Είστε σίγουροι ότι θέλετε να αποχωρήσετε από αυτήν την ομάδα;',
        'leave_group_btn': 'Αποχώρηση',
        'cannot_leave_active_group': 'Δεν είναι δυνατή η αποχώρηση από την ενεργή ομάδα.',
        'leave_group_error': 'Σφάλμα: %s',
    },
    'uk': {
        'confirm_leave_group_title': 'Вийти з групи',
        'confirm_leave_group_message': 'Ви впевнені, що хочете вийти з цієї групи?',
        'leave_group_btn': 'Вийти',
        'cannot_leave_active_group': 'Неможливо вийти з активної групи.',
        'leave_group_error': 'Помилка: %s',
    },
    'ro': {
        'confirm_leave_group_title': 'Părăsește grupul',
        'confirm_leave_group_message': 'Sunteți sigur că doriți să părăsiți acest grup?',
        'leave_group_btn': 'Părăsește',
        'cannot_leave_active_group': 'Nu se poate părăsi grupul activ.',
        'leave_group_error': 'Eroare: %s',
    },
    'cs': {
        'confirm_leave_group_title': 'Opustit skupinu',
        'confirm_leave_group_message': 'Opravdu chcete opustit tuto skupinu?',
        'leave_group_btn': 'Opustit',
        'cannot_leave_active_group': 'Nelze opustit aktivní skupinu.',
        'leave_group_error': 'Chyba: %s',
    },
    'hu': {
        'confirm_leave_group_title': 'Csoport elhagyása',
        'confirm_leave_group_message': 'Biztosan el akarja hagyni ezt a csoportot?',
        'leave_group_btn': 'Elhagyás',
        'cannot_leave_active_group': 'Az aktív csoport nem hagyható el.',
        'leave_group_error': 'Hiba: %s',
    }
}

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

count = 0
for lang, trans_dict in translations.items():
    pattern = r"('" + lang + r"':\s*\{)"
    match = re.search(pattern, content)
    
    if match and "'confirm_leave_group_title'" not in content[match.end():match.end()+2000]:
        insert_pos = match.end()
        injection = "\n"
        for key, val in trans_dict.items():
            val = val.replace("'", "\\'")
            injection += f"      '{key}': '{val}',\n"
        
        content = content[:insert_pos] + injection + content[insert_pos:]
        print(f"Injected for {lang}")
        count += 1

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"Done. Injected {count} languages.")
