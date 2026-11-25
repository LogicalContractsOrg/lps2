# Logical English for LPS in other languages

*Kind: guide · Audience: authors who write LPS programs in a language that is not English · Status: current (2026-11-25)*

You can write an LPS program in Logical English in six natural languages. Logical
English (LE) is a way to write a program in the sentences of a natural language.
Each language has its own version of Logical English:

| Language | Name of its Logical English | First sentence of an LPS program |
|---|---|---|
| English | Logical English | `the target language is: lps.` |
| Portuguese | Português Lógico | `a linguagem alvo é: lps.` |
| Spanish | Español Lógico | `el lenguaje objetivo es: lps.` |
| French | Français Logique | `la langue cible est: lps.` |
| Italian | Italiano Logico | `il linguaggio obiettivo è: lps.` |
| German | Logisches Deutsch | `die Zielsprache ist: lps.` |

A program has the same meaning in each language. Only two things change: the
keywords, and the words that the author selects for the sentences of the program.
LPS2 reads the program with Logical English 2 (LE2), the sister system. LE2 has the
keywords of each language. Thus LPS2 needs an LE2 installation to open a `.le`
file, in each language.

This page has two parts. The first part gives the keywords that an LPS program
shares with a program that has no time. The second part gives the keywords that
only an LPS program has.

## Contents

- [The keywords of timeless Logical English](#the-keywords-of-timeless-logical-english)
- [The keywords that LPS adds](#the-keywords-that-lps-adds)
- [A program in Logisches Deutsch](#a-program-in-logisches-deutsch)
- [German sentences](#german-sentences)
- [Numbers](#numbers)
- [Where the examples are](#where-the-examples-are)
- [See also](#see-also)

## The keywords of timeless Logical English

A *timeless* program is a program of rules and facts with no time in it: its first
sentence ends in `prolog.`, and it answers queries. An LPS program uses the same
keywords for its templates, its rules, its scenarios and its queries. A *template*
is the pattern of a sentence, with a slot for each thing that changes. A *scenario*
is a set of facts with a name. A *query* is a question to the program.

The table gives the main form of each keyword. Some keywords have a second form,
which the table shows after a comma.

| | English | Português | Español | Français | Italiano | Deutsch |
|---|---|---|---|---|---|---|
| the first sentence | `the target language is` | `a linguagem alvo é` | `el lenguaje objetivo es` | `la langue cible est` | `il linguaggio obiettivo è` | `die Zielsprache ist` |
| templates | `the templates are` | `os modelos são` | `las plantillas son` | `les modèles sont` | `i modelli sono` | `die Vorlagen sind` |
| the knowledge base | `the knowledge base` | `a base de conhecimento` | `la base de conocimiento` | `la base de connaissances` | `la base di conoscenza` | `die Wissensbasis` |
| … includes | `includes` | `inclui` | `incluye` | `comprend` | `include` | `enthält` |
| if | `if` | `se` | `si` | `si` | `se` | `wenn`, `falls` |
| and | `and` | `e` | `y` | `et` | `e` | `und` |
| or | `or` | `ou` | `o` | `ou` | `o` | `oder` |
| negation | `it is not the case that` | `não é o caso que` | `no es el caso que` | `il n'est pas vrai que` | `non è il caso che` | `es ist nicht der Fall, dass` |
| for all cases | `for all cases in which` | `para todos os casos em que` | `para todos los casos en que` | `pour tous les cas où` | `per tutti i casi in cui` | `für alle Fälle, in denen` |
| … it is the case that | `it is the case that` | `é o caso que` | `es el caso que` | `il est avéré que` | `è il caso che` | `ist es der Fall, dass` |
| scenario | `scenario` | `cenário` | `escenario` | `scénario` | `scenario` | `Szenario` |
| query | `query` | `consulta` | `consulta` | `requête` | `interrogazione` | `Abfrage` |
| expects | `expects` | `espera` | `espera` | `attend` | `attende` | `erwartet` |
| answers | `answers` | `respostas` | `respuestas` | `les réponses` | `risposte` | `die Antworten` |
| known as | `known as` | `conhecido como` | `conocido como` | `connu comme` | `noto come` | `bekannt als` |
| which | `which` | `qual` | `cuál` | `quel` | `quale` | `welcher` |

The guide [Logical English in other languages](https://le2.logicalcontracts.com/docs/user/guide/languages)
of LE2 gives the other keywords of timeless Logical English, and the rules for
numbers and dates.

## The keywords that LPS adds

An LPS program describes things that change in time. A *fluent* is a fact that is
true for a period of time. An *event* is something that occurs between two times.
An *action* is an event that the program does. A *reactive rule* tells the program
what to do when something becomes true. A *causal law* tells how an event changes
a fluent. A *constraint* tells what must not occur.

| | English | Português | Español | Français | Italiano | Deutsch |
|---|---|---|---|---|---|---|
| fluents | `the fluents are` | `os fluentes são` | `los fluentes son` | `les fluents sont` | `i fluenti sono` | `die Fluenten sind` |
| events | `the events are` | `os eventos são` | `los eventos son` | `les événements sont` | `gli eventi sono` | `die Ereignisse sind` |
| actions | `the actions are` | `as ações são` | `las acciones son` | `les actions sont` | `le azioni sono` | `die Aktionen sind` |
| at the start | `initially` | `inicialmente` | `inicialmente` | `initialement` | `inizialmente` | `anfangs` |
| reactive rule: if | `if` | `se` | `si` | `si` | `se` | `wenn`, `falls` |
| … then | `then` | `então` | `entonces` | `alors` | `allora` | `dann` |
| causal law: when | `when` | `quando` | `cuando` | `quand` | `quando` | `sobald` |
| constraint | `it must not be true that` | `não pode ser verdade que` | `no puede ser cierto que` | `il ne doit pas être vrai que` | `non deve essere vero che` | `es darf nicht sein, dass` |
| goal | `the goal is that` | `o objetivo é que` | `el objetivo es que` | `le but est que` | `l'obiettivo è che` | `das Ziel ist, dass` |
| update: that is | `that is` | `que é` | `que es` | `qui est` | `che è` | `das ist` |
| … becomes | `becomes` | `torna-se` | `se convierte en` | `devient` | `diventa` | `wird zu` |
| time: at | `at` | `em` | `en` | `à` | `a` | `zu` |
| time: from | `from` | `de` | `desde` | `de` | `da` | `von` |
| … to | `to` | `até` | `hasta` | `jusqu'à` | `fino a` | `bis zu` |
| the noun of a time | `time` | `tempo`, `momento` | `tiempo`, `momento` | `temps`, `moment` | `tempo`, `momento` | `Zeitpunkt`, `Zeit` |
| the maximum time | `the maximum time is` | `o tempo máximo é` | `el tiempo máximo es` | `le temps maximum est` | `il tempo massimo è` | `die maximale Zeit ist` |
| the maximum real time | `the maximum real time is` | `o tempo real máximo é` | `el tiempo real máximo es` | `le temps réel maximum est` | `il tempo reale massimo è` | `die maximale Echtzeit ist` |
| the minimum cycle time | `the minimum cycle time is` | `o tempo mínimo de ciclo é` | `el tiempo mínimo de ciclo es` | `le temps de cycle minimum est` | `il tempo minimo di ciclo è` | `die minimale Zykluszeit ist` |
| replace a law | `this law replaces law` | `esta lei substitui a lei` | `esta ley sustituye la ley` | `cette loi remplace la loi` | `questa legge sostituisce la legge` | `diese Kausalregel ersetzt die Kausalregel` |
| replace a constraint | `this constraint replaces constraint` | `esta restrição substitui a restrição` | `esta restricción sustituye la restricción` | `cette contrainte remplace la contrainte` | `questo vincolo sostituisce il vincolo` | `diese Integritätsbedingung ersetzt die Integritätsbedingung` |
| default value | `by default` | `por omissão` | `por defecto` | `par défaut` | `per impostazione predefinita` | `als Standardwert` |

The reference [Logical English for LPS](../reference/le-for-lps.md) describes each
of these constructs in English.

## A program in Logisches Deutsch

Below is the example `examples/de/feuer.le`. It is the German version of
`examples/le/fire_simple.le`:

```
Die Zielsprache ist: lps.

Die maximale Zeit ist 5.

Die Ereignisse sind:
    das Feuer wird bekämpft; bekannt als deal_with_fire.

Die Aktionen sind:
    das Feuer wird gelöscht; bekannt als eliminate.
    alle fliehen; bekannt als escape.

Die Fluenten sind:
    es gibt ein Feuer; bekannt als fire.

Die Wissensbasis Feuer enthält:

Anfangs gibt es ein Feuer.

Wenn es zu einem ersten Zeitpunkt ein Feuer gibt,
dann wird das Feuer vom ersten Zeitpunkt bis zu einem zweiten Zeitpunkt bekämpft.

Das Feuer wird von einem ersten Zeitpunkt bis zu einem zweiten Zeitpunkt bekämpft,
wenn das Feuer vom ersten Zeitpunkt bis zum zweiten Zeitpunkt gelöscht wird.

Das Feuer wird von einem ersten Zeitpunkt bis zu einem zweiten Zeitpunkt bekämpft,
wenn alle vom ersten Zeitpunkt bis zum zweiten Zeitpunkt fliehen.

Wenn das Feuer gelöscht wird,
dann gibt es nicht mehr ein Feuer.
```

Do these steps:

1. Open the example `de/feuer` in the IDE.
2. Click **Run**. The **Timeline** shows the fire at time 1, and the event
   `deal_with_fire` from time 1 to time 2.
3. Open the example `le/fire_simple` in a second tab and click **Run**.

The two timelines are the same. The names after `bekannt als` are the names after
`known as` in the English program, and LPS2 reads the two programs into the same
rules.

## German sentences

German changes the position of the verb and the endings of words. Logisches
Deutsch reads these sentences as German writes them:

- **A template is a main clause**, with its verb in the second position: `das
  Feuer wird bekämpft`.
- **After `wenn`, `falls`, `sobald` and `dass`, the verb is at the end**: `wenn
  das Feuer … gelöscht wird`, `dass es ein Feuer gibt`.
- **After `dann` and `anfangs`, the verb comes immediately**, before the
  subject: `dann wird das Feuer … bekämpft`, `Anfangs gibt es ein Feuer`.
- **The time is before the last words of the sentence**, not after them: `das
  Feuer wird von einem ersten Zeitpunkt bis zu einem zweiten Zeitpunkt bekämpft`.
  A time at the end of the sentence is also accepted.
- **The noun of a time is `Zeitpunkt`** (or `Zeit`, or `Moment`). `ein erster
  Zeitpunkt`, `der erste Zeitpunkt` and `dem ersten Zeitpunkt` are the same time.
- **`vom` and `zum` are `von dem` and `zu dem`**: `vom ersten Zeitpunkt bis zum
  zweiten Zeitpunkt`.
- **A comma between clauses is permitted**: before `wenn`, `dann`, `dass`, `und`.
  The tables above show `es ist nicht der Fall, dass` with its comma. The comma
  is not a part of the keyword.
- **The first word of a sentence can have a capital letter**: `Die Fluenten
  sind:`, `Wenn …`, `Anfangs …`.
- **`wenn` is "if" and also "when".** A rule `wenn … dann …` whose conclusion
  names an event or an action is a reactive rule. A rule `wenn <an event> dann
  …` whose conclusion only tells which fluents become true or false is a causal
  law, as a rule with `sobald` is: `Wenn das Feuer gelöscht wird, dann gibt es
  nicht mehr ein Feuer.`
- **`nicht mehr` and `nicht` are a negation.** In the conclusion of a causal
  law, `nicht mehr` tells that the fluent stops: `dann ist die Rechnung nicht
  mehr offen`. `kein` is not read as a negation.
- **The genitive.** Write the fluent with a genitive: `der Kontostand *einer
  Person* beträgt *einen Betrag*`. Then `der Kontostand des Zahlers` and `der
  Kontostand von Bob` are sentences of that fluent.
- **An update has two forms.** The fluent comes first, then `das ist` and the old
  value, then `wird zu` and the new value: `der Kontostand des Zahlers, das ist
  eine Zahl Z, wird zu Z - B`. After `dann`, the verb `wird` comes first: `dann
  wird der Kontostand des Empfängers, das ist eine Zahl E, zu E + B`. A variable
  with a letter (`eine Zahl Z`) makes the calculation easy to read.
- **A causal law needs `dann`.** `Sobald das Feuer gelöscht wird, gibt es nicht
  mehr ein Feuer.` (without `dann`) is not read.

The guide of LE2 gives all the rules of Logisches Deutsch, and the sentences that
it does not read.

In the other five languages, the words of a sentence have the order of the
template, and the time is at the end of the sentence, as in English: `o fogo é
tratado de um primeiro tempo até um segundo tempo`.

## Numbers

In Portuguese, Spanish, French, Italian and German, a comma between two digits is
the decimal comma: `1,5` is one and a half. A point divides the thousands:
`1.250.000`. A time in a scenario is a whole number, in each language: `Fariba
überweist 10 an Bob von 1 bis 2`.

## Where the examples are

- `examples/de/`: two programs in Logisches Deutsch, `feuer` and `ueberweisung`.
  Each is the translation of a program of `examples/le/`.
- `examples/le/`: the programs in English.

There are no example LPS programs in Portuguese, Spanish, French or Italian yet.

## See also

- [Logical English for LPS](../reference/le-for-lps.md): the reference, in English.
- [Using the editor](ide.md): the manual of the IDE.
- [Logical English in other languages](https://le2.logicalcontracts.com/docs/user/guide/languages):
  the guide of LE2, with the rules of each language.
