# Logisches Deutsch — LPS-Programme auf Deutsch

LPS-Programme in Logischem Deutsch, dem Logical English der deutschen Sprache.
Jedes Programm beginnt mit `die Zielsprache ist: lps.` und ist die deutsche
Fassung eines Programms aus [`le/`](../le/). Die Sätze stehen so, wie man
Deutsch schreibt: das Verb am Ende nach `wenn` und `dass`, und unmittelbar
nach `dann` und `anfangs`.

## Zum Einstieg
- [Das Feuer](feuer.le): die kleinste reaktive Regel. Wenn es ein Feuer gibt,
  dann wird das Feuer bekämpft.
- [Die Überweisung](ueberweisung.le): zwei Konten, zwei reaktive Regeln, und
  drei Integritätsbedingungen, die sagen, wer überweisen darf.

## Ausprobieren
1. Öffnen Sie [das Feuer](feuer.le) und klicken Sie auf **Run**. Die
   **Timeline** zeigt das Feuer zum Zeitpunkt 1 und das Ereignis
   `deal_with_fire` von 1 bis 2.
2. Öffnen Sie in einem zweiten Tab [die englische Fassung](../le/fire_simple.le)
   und klicken Sie auf **Run**. Die beiden Abläufe sind gleich.
3. Öffnen Sie [die Überweisung](ueberweisung.le) und klicken Sie auf **Run**.
   Fariba überweist 10 an Bob, Bob überweist 10 zurück, und so weiter. Am Ende
   haben beide 50.
4. Wählen Sie **View ▸ Legal view**. Die Ansicht sagt, wer was tun darf.

## Mehr
- [LPS programs in other languages](/docs/user/guide/languages): the keywords
  of each language, and how German sentences are read (in English).
- [Logical English for LPS](/docs/user/reference/le-for-lps): the reference
  (in English).
