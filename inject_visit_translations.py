import re
import json

file_path = r'c:\manger3\lib\l10n\app_translations.dart'

translations = {
    'ar': {
        'home_visit': 'زيارة منزلية',
        'phone_call': 'مكالمة هاتفية',
        'external_meeting': 'مقابلة خارجية',
        'study_follow_up': 'متابعة دراسية',
        'spiritual_activity': 'نشاط روحي',
    },
    'fr': {
        'home_visit': 'Visite à domicile',
        'phone_call': 'Appel téléphonique',
        'external_meeting': 'Réunion externe',
        'study_follow_up': 'Suivi des études',
        'spiritual_activity': 'Activité spirituelle',
    },
    'es': {
        'home_visit': 'Visita domiciliaria',
        'phone_call': 'Llamada telefónica',
        'external_meeting': 'Reunión externa',
        'study_follow_up': 'Seguimiento de estudio',
        'spiritual_activity': 'Actividad espiritual',
    },
    'de': {
        'home_visit': 'Hausbesuch',
        'phone_call': 'Telefonanruf',
        'external_meeting': 'Externes Treffen',
        'study_follow_up': 'Studienverfolgung',
        'spiritual_activity': 'Spirituelle Aktivität',
    },
    'it': {
        'home_visit': 'Visita domiciliare',
        'phone_call': 'Telefonata',
        'external_meeting': 'Riunione esterna',
        'study_follow_up': 'Monitoraggio studio',
        'spiritual_activity': 'Attività spirituale',
    },
    'pt': {
        'home_visit': 'Visita domiciliar',
        'phone_call': 'Chamada telefônica',
        'external_meeting': 'Reunião externa',
        'study_follow_up': 'Acompanhamento de estudos',
        'spiritual_activity': 'Atividade espiritual',
    },
    'nl': {
        'home_visit': 'Huisbezoek',
        'phone_call': 'Telefoongesprek',
        'external_meeting': 'Externe vergadering',
        'study_follow_up': 'Studie opvolging',
        'spiritual_activity': 'Spirituele activiteit',
    },
    'ru': {
        'home_visit': 'Посещение на дому',
        'phone_call': 'Телефонный звонок',
        'external_meeting': 'Внешняя встреча',
        'study_follow_up': 'Контроль за учебой',
        'spiritual_activity': 'Духовная деятельность',
    },
    'pl': {
        'home_visit': 'Wizyta domowa',
        'phone_call': 'Rozmowa telefoniczna',
        'external_meeting': 'Spotkanie zewnętrzne',
        'study_follow_up': 'Śledzenie nauki',
        'spiritual_activity': 'Aktywność duchowa',
    },
    'sv': {
        'home_visit': 'Hembesök',
        'phone_call': 'Telefonsamtal',
        'external_meeting': 'Externt möte',
        'study_follow_up': 'Studieuppföljning',
        'spiritual_activity': 'Andlig aktivitet',
    },
    'el': {
        'home_visit': 'Επίσκεψη στο σπίτι',
        'phone_call': 'Τηλεφωνική κλήση',
        'external_meeting': 'Εξωτερική Συνάντηση',
        'study_follow_up': 'Παρακολούθηση Σπουδών',
        'spiritual_activity': 'Πνευματική Δραστηριότητα',
    },
    'uk': {
        'home_visit': 'Візит додому',
        'phone_call': 'Телефонний дзвінок',
        'external_meeting': 'Зовнішня зустріч',
        'study_follow_up': 'Відстеження навчання',
        'spiritual_activity': 'Духовна діяльність',
    },
    'ro': {
        'home_visit': 'Vizită la domiciliu',
        'phone_call': 'Apel telefonic',
        'external_meeting': 'Întâlnire externă',
        'study_follow_up': 'Urmărirea studiilor',
        'spiritual_activity': 'Activitate spirituală',
    },
    'cs': {
        'home_visit': 'Návštěva doma',
        'phone_call': 'Telefonní hovor',
        'external_meeting': 'Externí setkání',
        'study_follow_up': 'Sledování studia',
        'spiritual_activity': 'Duchovní aktivita',
    },
    'hu': {
        'home_visit': 'Házi látogatás',
        'phone_call': 'Telefonhívás',
        'external_meeting': 'Külső találkozó',
        'study_follow_up': 'Tanulmányok nyomon követése',
        'spiritual_activity': 'Szellemi tevékenység',
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
        # We can extract the block for this language and check if 'home_visit' is in it
        next_lang_match = re.search(r"'[a-z]{2}':\s*\{", content[insert_pos:])
        end_pos = insert_pos + next_lang_match.start() if next_lang_match else len(content)
        block = content[insert_pos:end_pos]
        
        if "'home_visit'" not in block:
            injection = "\n"
            for key, val in trans_dict.items():
                val = val.replace("'", "\\'")
                injection += f"      '{key}': '{val}',\n"
            
            content = content[:insert_pos] + injection + content[insert_pos:]
            print(f"Injected visit translations for {lang}")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done.")
