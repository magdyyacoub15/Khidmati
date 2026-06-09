# -*- coding: utf-8 -*-
import re

translations = {
    'en': {
        'consecutive_absence_msg_1': '%s missed repeatedly, needs a check-in \U0001f4de',
        'consecutive_absence_msg_2': 'Reminder: %s hasn\'t attended lately, check on them today? \u2728',
        'consecutive_absence_msg_3': 'Repeated absence of %s needs love and care, don\'t forget them \U0001f64f',
        'least_visited_msg_1': '%s needs you to ask about them today \U0001f499',
        'least_visited_msg_2': 'Reminder: %s is one of the most in need of your care and visit right now \u2728',
        'least_visited_msg_3': 'Don\'t forget to check on %s today, your labor of love is great \U0001f64f',
        'least_visited_msg_4': 'Visiting %s today will have a great impact on their life \U0001f33f',
        'morning_reminder_title': 'Morning Reminder \u2600\ufe0f',
        'evening_reminder_title': 'Evening Reminder \u2728',
        'evening_reminder_body': 'Don\'t forget to check on %s today \U0001f499',
    },
    'ar': {
        'consecutive_absence_msg_1': 'المخدوم %s غاب أكتر من مرة، محتاج سؤال ضروري منك \U0001f4de',
        'consecutive_absence_msg_2': 'تذكير: %s مش ظاهر بقاله فترة، ممكن تطمن عليه النهاردة؟ \u2728',
        'consecutive_absence_msg_3': 'الغياب المتكرر لـ %s محتاج وقفة حب واحتواء، ماتنساش تكلمه \U0001f64f',
        'least_visited_msg_1': 'المخدوم %s محتاج سؤالك عليه النهارده \U0001f499',
        'least_visited_msg_2': 'تذكير: %s من أكتر المخدومين اللي محتاجين اهتمامك وزيارتك الفترة دي \u2728',
        'least_visited_msg_3': 'ماتنساش تطمن على %s النهاردة، تعب محبتك كبير \U0001f64f',
        'least_visited_msg_4': 'افتقاد %s النهاردة هيكون له أثر كبير في حياته \U0001f33f',
        'morning_reminder_title': 'تذكير صباحي \u2600\ufe0f',
        'evening_reminder_title': 'تذكير مسائي \u2728',
        'evening_reminder_body': 'ماتنساش تطمن على المخدوم %s النهاردة \U0001f499',
    },
    'fr': {
        'consecutive_absence_msg_1': '%s a manqué à plusieurs reprises, a besoin d\'un suivi \U0001f4de',
        'consecutive_absence_msg_2': 'Rappel: %s n\'est pas venu dernièrement, prenez de ses nouvelles aujourd\'hui? \u2728',
        'consecutive_absence_msg_3': 'L\'absence répétée de %s nécessite amour et attention, ne l\'oubliez pas \U0001f64f',
        'least_visited_msg_1': '%s a besoin que vous preniez de ses nouvelles aujourd\'hui \U0001f499',
        'least_visited_msg_2': 'Rappel: %s est parmi ceux qui ont le plus besoin de vos soins et de votre visite en ce moment \u2728',
        'least_visited_msg_3': 'N\'oubliez pas de prendre des nouvelles de %s aujourd\'hui, votre travail d\'amour est grand \U0001f64f',
        'least_visited_msg_4': 'Rendre visite à %s aujourd\'hui aura un grand impact sur sa vie \U0001f33f',
        'morning_reminder_title': 'Rappel matinal \u2600\ufe0f',
        'evening_reminder_title': 'Rappel du soir \u2728',
        'evening_reminder_body': 'N\'oubliez pas de prendre des nouvelles de %s aujourd\'hui \U0001f499',
    },
    'es': {
        'consecutive_absence_msg_1': '%s faltó repetidamente, necesita un seguimiento \U0001f4de',
        'consecutive_absence_msg_2': 'Recordatorio: %s no ha asistido últimamente, ¿puedes ver cómo le va hoy? \u2728',
        'consecutive_absence_msg_3': 'La ausencia repetida de %s necesita amor y cuidado, no lo olvides \U0001f64f',
        'least_visited_msg_1': '%s necesita que preguntes por él/ella hoy \U0001f499',
        'least_visited_msg_2': 'Recordatorio: %s es uno de los que más necesita tu cuidado y visita en este momento \u2728',
        'least_visited_msg_3': 'No olvides ver cómo está %s hoy, tu labor de amor es grande \U0001f64f',
        'least_visited_msg_4': 'Visitar a %s hoy tendrá un gran impacto en su vida \U0001f33f',
        'morning_reminder_title': 'Recordatorio matutino \u2600\ufe0f',
        'evening_reminder_title': 'Recordatorio vespertino \u2728',
        'evening_reminder_body': 'No olvides ver cómo está %s hoy \U0001f499',
    },
    'de': {
        'consecutive_absence_msg_1': '%s hat wiederholt gefehlt, braucht einen Check-in \U0001f4de',
        'consecutive_absence_msg_2': 'Erinnerung: %s war in letzter Zeit nicht da, heute nach ihm/ihr sehen? \u2728',
        'consecutive_absence_msg_3': 'Wiederholte Abwesenheit von %s braucht Liebe und Fürsorge, vergiss sie nicht \U0001f64f',
        'least_visited_msg_1': '%s braucht dich, um heute nach ihm/ihr zu fragen \U0001f499',
        'least_visited_msg_2': 'Erinnerung: %s gehört zu denen, die deine Fürsorge und deinen Besuch jetzt am meisten brauchen \u2728',
        'least_visited_msg_3': 'Vergiss nicht, heute nach %s zu sehen, deine Liebesmühe ist groß \U0001f64f',
        'least_visited_msg_4': 'Ein Besuch bei %s heute wird einen großen Einfluss auf sein/ihr Leben haben \U0001f33f',
        'morning_reminder_title': 'Morgendliche Erinnerung \u2600\ufe0f',
        'evening_reminder_title': 'Abendliche Erinnerung \u2728',
        'evening_reminder_body': 'Vergiss nicht, heute nach %s zu sehen \U0001f499',
    },
    'it': {
        'consecutive_absence_msg_1': '%s è stato assente ripetutamente, ha bisogno di un controllo \U0001f4de',
        'consecutive_absence_msg_2': 'Promemoria: %s non è venuto ultimamente, controllalo oggi? \u2728',
        'consecutive_absence_msg_3': 'Le assenze ripetute di %s hanno bisogno di amore e cure, non dimenticarlo \U0001f64f',
        'least_visited_msg_1': '%s ha bisogno che tu chieda di lui/lei oggi \U0001f499',
        'least_visited_msg_2': 'Promemoria: %s è uno dei più bisognosi delle tue cure e visite in questo momento \u2728',
        'least_visited_msg_3': 'Non dimenticare di controllare %s oggi, la tua opera d\'amore è grande \U0001f64f',
        'least_visited_msg_4': 'Visitare %s oggi avrà un grande impatto sulla sua vita \U0001f33f',
        'morning_reminder_title': 'Promemoria mattutino \u2600\ufe0f',
        'evening_reminder_title': 'Promemoria serale \u2728',
        'evening_reminder_body': 'Non dimenticare di controllare %s oggi \U0001f499',
    },
    'pt': {
        'consecutive_absence_msg_1': '%s faltou repetidamente, precisa de um acompanhamento \U0001f4de',
        'consecutive_absence_msg_2': 'Lembrete: %s não tem comparecido ultimamente, verifique hoje? \u2728',
        'consecutive_absence_msg_3': 'A ausência repetida de %s precisa de amor e cuidado, não se esqueça \U0001f64f',
        'least_visited_msg_1': '%s precisa que você pergunte por ele(a) hoje \U0001f499',
        'least_visited_msg_2': 'Lembrete: %s é um dos que mais precisam do seu cuidado e visita agora \u2728',
        'least_visited_msg_3': 'Não se esqueça de verificar %s hoje, seu trabalho de amor é grande \U0001f64f',
        'least_visited_msg_4': 'Visitar %s hoje terá um grande impacto em sua vida \U0001f33f',
        'morning_reminder_title': 'Lembrete matinal \u2600\ufe0f',
        'evening_reminder_title': 'Lembrete noturno \u2728',
        'evening_reminder_body': 'Não se esqueça de verificar %s hoje \U0001f499',
    },
    'nl': {
        'consecutive_absence_msg_1': '%s was herhaaldelijk afwezig, heeft even aandacht nodig \U0001f4de',
        'consecutive_absence_msg_2': 'Herinnering: %s is er de laatste tijd niet, kijk vandaag even naar hem/haar om? \u2728',
        'consecutive_absence_msg_3': 'Herhaaldelijke afwezigheid van %s heeft liefde en zorg nodig, vergeet ze niet \U0001f64f',
        'least_visited_msg_1': '%s heeft nodig dat je vandaag naar hem/haar vraagt \U0001f499',
        'least_visited_msg_2': 'Herinnering: %s is een van degenen die op dit moment het meest jouw zorg en bezoek nodig heeft \u2728',
        'least_visited_msg_3': 'Vergeet niet vandaag naar %s om te kijken, jouw liefdeswerk is groot \U0001f64f',
        'least_visited_msg_4': 'Je bezoek aan %s vandaag zal een grote impact op zijn/haar leven hebben \U0001f33f',
        'morning_reminder_title': 'Ochtendherinnering \u2600\ufe0f',
        'evening_reminder_title': 'Avondherinnering \u2728',
        'evening_reminder_body': 'Vergeet niet vandaag naar %s om te kijken \U0001f499',
    },
    'ru': {
        'consecutive_absence_msg_1': '%s неоднократно отсутствовал(а), требуется проверка \U0001f4de',
        'consecutive_absence_msg_2': 'Напоминание: %s в последнее время не посещает, проверите его/ее сегодня? \u2728',
        'consecutive_absence_msg_3': 'Повторное отсутствие %s требует любви и заботы, не забывайте о нем/ней \U0001f64f',
        'least_visited_msg_1': '%s нуждается в том, чтобы вы спросили о нем/ней сегодня \U0001f499',
        'least_visited_msg_2': 'Напоминание: %s - один/одна из тех, кто больше всего нуждается в вашей заботе и посещении прямо сейчас \u2728',
        'least_visited_msg_3': 'Не забудьте сегодня проведать %s, ваш труд любви велик \U0001f64f',
        'least_visited_msg_4': 'Общение с %s сегодня окажет огромное влияние на его/ее жизнь \U0001f33f',
        'morning_reminder_title': 'Утреннее напоминание \u2600\ufe0f',
        'evening_reminder_title': 'Вечернее напоминание \u2728',
        'evening_reminder_body': 'Не забудьте сегодня проведать %s \U0001f499',
    },
    'pl': {
        'consecutive_absence_msg_1': '%s nie było z nami kilka razy, potrzebuje wsparcia \U0001f4de',
        'consecutive_absence_msg_2': 'Przypomnienie: %s nie był ostatnio obecny, sprawdzisz co u niego dzisiaj? \u2728',
        'consecutive_absence_msg_3': 'Powtarzająca się nieobecność %s wymaga miłości i troski, nie zapomnij \U0001f64f',
        'least_visited_msg_1': '%s potrzebuje, abyś o niego dzisiaj zapytał \U0001f499',
        'least_visited_msg_2': 'Przypomnienie: %s jest jedną z osób najbardziej potrzebujących Twojej troski i wizyty w tej chwili \u2728',
        'least_visited_msg_3': 'Nie zapomnij sprawdzić co u %s dzisiaj, Twoja praca miłości jest wielka \U0001f64f',
        'least_visited_msg_4': 'Wizyta u %s dzisiaj będzie miała wielki wpływ na jego/jej życie \U0001f33f',
        'morning_reminder_title': 'Poranne przypomnienie \u2600\ufe0f',
        'evening_reminder_title': 'Wieczorne przypomnienie \u2728',
        'evening_reminder_body': 'Nie zapomnij sprawdzić co u %s dzisiaj \U0001f499',
    }
}

file_path = 'c:/manger3/lib/l10n/app_translations.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# For each language, find the dictionary and inject
for lang, trans_dict in translations.items():
    if not trans_dict: continue
    
    # We find the start of the language dictionary
    pattern = r"('" + lang + r"':\s*\{)"
    match = re.search(pattern, content)
    
    if match:
        dict_start = match.end()
        # Find the end of this dictionary block (approximate, assuming it's closed by '},' or '}')
        # A better way is to find the next lang key or the end of the map
        next_pattern = r"\s+'[a-z]{2}':\s*\{|\s+\};"
        next_match = re.search(next_pattern, content[dict_start:])
        
        dict_body = ""
        if next_match:
            dict_end = dict_start + next_match.start()
            dict_body = content[dict_start:dict_end]
            
            # Check for existing keys and update or add
            for key, val in trans_dict.items():
                val_escaped = val.replace("'", "\\'")
                key_pattern = r"'" + key + r"':\s*'.*?',?\n"
                if re.search(key_pattern, dict_body):
                    # Update existing
                    dict_body = re.sub(key_pattern, f"      '{key}': '{val_escaped}',\n", dict_body)
                else:
                    # Prepend new
                    dict_body = f"\n      '{key}': '{val_escaped}'," + dict_body
            
            content = content[:dict_start] + dict_body + content[dict_end:]
            print(f"Updated/Injected translations for {lang}")
        else:
            print(f"Could not find end of dictionary for {lang}")
    else:
        print(f"Could not find dictionary for {lang}")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done.")

