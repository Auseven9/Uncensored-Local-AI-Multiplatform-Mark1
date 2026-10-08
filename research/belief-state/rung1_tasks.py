"""
Expanded probe bank for rung-1 (50+ questions). Import into rung1_colab.py:
    from rung1_tasks import SCEN
Each scenario packs MANY facts; each question needs only a few — so scratchpad
dumps all, RAG retrieves relevant, belief-state decodes relevant. That's the fair
fight. Mix of names, numbers, dates, relations, preferences to stress recall.
"""
SCEN = [
 {"facts":{"project":"ALESIS","device":"Samsung S24 Ultra","model_size":"4B","lang":"Dart",
           "chip":"Snapdragon 8 Gen 3","ram":"12GB","owner":"Dylon","goal":"local AI","db":"SQLite"},
  "qa":[("What device?","S24 Ultra"),("Who owns it?","Dylon"),("What language?","Dart"),
        ("How much RAM?","12GB"),("What database?","SQLite")]},
 {"facts":{"pet":"a corgi named Biscuit","city":"Lisbon","job":"luthier","car":"blue Saab",
           "sister":"Mara","allergy":"peanuts","instrument":"cello","coffee":"oat flat white"},
  "qa":[("What job?","luthier"),("Pet's name?","Biscuit"),("Which city?","Lisbon"),
        ("Allergic to what?","peanuts"),("What car?","Saab")]},
 {"facts":{"deadline":"March 3rd","budget":"4000 dollars","lead":"Dana","client":"Northwind",
           "stack":"Flutter","repo":"alesis-core","reviewer":"Sam","status":"in review"},
  "qa":[("Who is lead?","Dana"),("The budget?","4000"),("Who reviews?","Sam"),
        ("Which client?","Northwind"),("What deadline?","March 3")]},
 {"facts":{"flight":"BA249","seat":"14C","gate":"B22","depart":"7:40pm",
           "hotel":"The Marlowe","room":"508","confirmation":"XK7T2","bags":"2"},
  "qa":[("Which seat?","14C"),("What gate?","B22"),("Hotel name?","Marlowe"),
        ("Room number?","508"),("Confirmation code?","XK7T2")]},
 {"facts":{"recipe":"carbonara","eggs":"3","pecorino":"80g","guanciale":"120g","pasta":"spaghetti",
           "serves":"2","time":"20 minutes","tip":"no cream"},
  "qa":[("How many eggs?","3"),("What cheese?","pecorino"),("Serves how many?","2"),
        ("Which pasta?","spaghetti"),("Cooking time?","20")]},
 {"facts":{"patient":"Room 4","med":"amoxicillin","dose":"500mg","freq":"three times daily",
           "allergy":"sulfa","doctor":"Okafor","start":"Tuesday"},
  "qa":[("Which drug?","amoxicillin"),("What dose?","500"),("Allergic to?","sulfa"),
        ("Which doctor?","Okafor"),("How often?","three times")]},
 {"facts":{"team":"Rovers","captain":"Ortiz","coach":"Villa","stadium":"Elm Park",
           "colors":"green and white","founded":"1921","rival":"City"},
  "qa":[("Who is captain?","Ortiz"),("Which stadium?","Elm Park"),("Team colors?","green"),
        ("Founded when?","1921"),("Who is coach?","Villa")]},
 {"facts":{"wifi":"Starlink-7A","password":"copper-otter-49","printer":"HP-2200","server":"nas01",
           "backup":"Sunday 2am","admin":"Priya","vpn":"on"},
  "qa":[("Wifi name?","Starlink-7A"),("Who is admin?","Priya"),("Backup when?","Sunday"),
        ("Which printer?","HP-2200"),("Server name?","nas01")]},
 {"facts":{"book":"The Glass Hours","author":"N. Reyes","pages":"312","chapter":"7",
           "character":"Ada","setting":"a lighthouse","genre":"mystery"},
  "qa":[("Who wrote it?","Reyes"),("Main character?","Ada"),("How many pages?","312"),
        ("What setting?","lighthouse"),("Which genre?","mystery")]},
 {"facts":{"car_service":"oil change","mileage":"62000","next":"67000","tire":"front-left low",
           "shop":"Vince's","cost":"89 dollars","oil":"5W-30"},
  "qa":[("Current mileage?","62000"),("Which shop?","Vince"),("What oil?","5W-30"),
        ("What cost?","89"),("Which tire is low?","front-left")]},
 {"facts":{"meeting":"Q3 review","when":"Thursday 10am","room":"Birch","owner":"Lena",
           "topic":"churn","decision":"ship v4","followup":"email board"},
  "qa":[("When is it?","Thursday"),("Which room?","Birch"),("Who owns it?","Lena"),
        ("What decision?","ship v4"),("Main topic?","churn")]},
 {"facts":{"plant":"monstera","water":"every 9 days","light":"indirect","fertilizer":"monthly",
           "repotted":"April","pot":"terracotta","issue":"yellow leaf"},
  "qa":[("Which plant?","monstera"),("Water how often?","9 days"),("What light?","indirect"),
        ("Repotted when?","April"),("What pot?","terracotta")]},
 {"facts":{"song":"Ember","artist":"Ko Vale","bpm":"104","key":"D minor","length":"3:48",
           "album":"Tidewater","producer":"J. Marsh"},
  "qa":[("Who is the artist?","Ko Vale"),("What BPM?","104"),("Which key?","D minor"),
        ("How long?","3:48"),("Which album?","Tidewater")]},
]
# 13 scenarios x 5 questions = 65 probes.
if __name__ == "__main__":
    print(sum(len(s["qa"]) for s in SCEN), "total questions across", len(SCEN), "scenarios")
