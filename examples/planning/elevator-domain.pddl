;; Miconic-style elevator, STRIPS subset.
;; Provenance: the Miconic domain family from IPC-2000 (Koehler & Schuster),
;; restated in plain STRIPS. The original is at
;; https://github.com/potassco/pddl-instances — this is the boarding/serving
;; core of it, with the floor ordering given as static facts.
(define (domain elevator)
  (:requirements :strips)
  (:predicates (passenger ?p) (floor ?f) (lift-at ?f)
               (origin ?p ?f) (destin ?p ?f)
               (boarded ?p) (served ?p) (above ?f1 ?f2))

  (:action board
    :parameters (?f ?p)
    :precondition (and (lift-at ?f) (origin ?p ?f))
    :effect (boarded ?p))

  (:action depart
    :parameters (?f ?p)
    :precondition (and (lift-at ?f) (destin ?p ?f) (boarded ?p))
    :effect (and (not (boarded ?p)) (served ?p)))

  (:action up
    :parameters (?f1 ?f2)
    :precondition (and (lift-at ?f1) (above ?f1 ?f2))
    :effect (and (lift-at ?f2) (not (lift-at ?f1))))

  (:action down
    :parameters (?f1 ?f2)
    :precondition (and (lift-at ?f1) (above ?f2 ?f1))
    :effect (and (lift-at ?f2) (not (lift-at ?f1)))))
