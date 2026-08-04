;; Towers of Hanoi, STRIPS.
;; Provenance: the classic encoding used in the IPC tutorials and in
;; planning.domains' `hanoi` domain — https://planning.domains/ — restated here
;; so this repository has no external fetch. Three pegs, N discs, one action.
(define (domain hanoi)
  (:requirements :strips)
  (:predicates (clear ?x) (on ?x ?y) (smaller ?x ?y))

  (:action move
    :parameters (?disc ?from ?to)
    :precondition (and (smaller ?disc ?to) (on ?disc ?from)
                       (clear ?disc) (clear ?to))
    :effect (and (clear ?from) (on ?disc ?to) (not (on ?disc ?from))
                 (not (clear ?to)))))
