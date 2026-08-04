;; Two discs — 3 moves optimal. Here so there is a hanoi problem that finishes
;; quickly under breadth-first search as well as under the heuristic.
(define (problem hanoi-2)
  (:domain hanoi)
  (:objects peg1 peg2 peg3 d1 d2)
  (:init (smaller d1 peg1) (smaller d1 peg2) (smaller d1 peg3)
         (smaller d2 peg1) (smaller d2 peg2) (smaller d2 peg3)
         (smaller d1 d2)
         (clear peg2) (clear peg3) (clear d1)
         (on d2 peg1) (on d1 d2))
  (:goal (and (on d2 peg3) (on d1 d2))))
