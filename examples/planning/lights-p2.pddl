;; A disjunctive goal with a quantifier: some lamp in the kitchen is on, or
;; the kitchen is tidy. `wall-switch` is a switch, not a room, so a plan that
;; tried to `go` to it would be refused by the types.
(define (problem lights-2)
  (:domain lights)
  (:objects kitchen - room
            ceiling-lamp - lamp
            wall-switch - switch)
  (:init (at hall) (door kitchen hall)
         (in wall-switch kitchen) (in ceiling-lamp kitchen)
         (wired wall-switch ceiling-lamp) (on ceiling-lamp) (broken ceiling-lamp))
  (:goal (or (exists (?l - lamp) (and (in ?l kitchen) (on ?l) (not (broken ?l))))
             (and (tidy kitchen) (not (on ceiling-lamp))))))
