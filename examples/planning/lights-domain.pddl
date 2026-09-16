;; Lights: a caretaker, rooms joined by doors, lamps on switches. Written for
;; LPS2 to exercise what goes beyond STRIPS: typed parameters and objects,
;; `or`, `exists`, `forall`, `imply` and `=` in preconditions, universal
;; conditional effects (`forall` + `when`), and negative or disjunctive goals.
;; Every construct here is translated, none is dropped (docs/user/integrations/pddl.md).
(define (domain lights)
  (:requirements :strips :typing :negative-preconditions :disjunctive-preconditions
                 :equality :quantified-preconditions :conditional-effects)
  (:types room - place
          lamp switch - thing)
  (:constants hall - room)
  (:predicates (at ?r - room) (door ?a - room ?b - room) (in ?t - thing ?r - room)
               (wired ?s - switch ?l - lamp) (on ?l - lamp) (broken ?l - lamp)
               (tidy ?r - room))

  ;; A door works both ways, whichever way round it was stated.
  (:action go
    :parameters (?from - room ?to - room)
    :precondition (and (at ?from) (not (= ?from ?to))
                       (or (door ?from ?to) (door ?to ?from)))
    :effect (and (not (at ?from)) (at ?to)))

  ;; A switch that works a lamp in the room turns on every lamp it is wired to.
  (:action flip
    :parameters (?s - switch ?r - room)
    :precondition (and (at ?r) (in ?s ?r) (exists (?l - lamp) (wired ?s ?l)))
    :effect (forall (?l - lamp) (when (and (wired ?s ?l) (not (broken ?l))) (on ?l))))

  (:action unplug
    :parameters (?l - lamp ?r - room)
    :precondition (and (at ?r) (in ?l ?r) (on ?l))
    :effect (not (on ?l)))

  ;; A room is tidied only when no broken lamp in it is on.
  (:action tidy-up
    :parameters (?r - room)
    :precondition (and (at ?r)
                       (forall (?l - lamp) (imply (and (in ?l ?r) (on ?l)) (not (broken ?l)))))
    :effect (tidy ?r)))
