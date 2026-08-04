;; Rovers, the sampling-and-communicating core.
;; Provenance: the IPC-2002 Rovers domain (Long & Fox), reduced to STRIPS
;; without the numeric energy fluents. Original family:
;; https://github.com/potassco/pddl-instances/tree/master/ipc-2002
(define (domain rover)
  (:requirements :strips)
  (:predicates (at ?x ?y) (can-traverse ?r ?x ?y)
               (at-soil-sample ?w) (at-rock-sample ?w)
               (equipped-for-soil ?r) (equipped-for-rock ?r) (equipped-for-imaging ?r)
               (empty ?s) (have-rock-analysis ?r ?w) (have-soil-analysis ?r ?w)
               (full ?s) (store-of ?s ?r)
               (communicated-soil-data ?w) (communicated-rock-data ?w)
               (visible ?x ?y) (at-lander ?l ?y) (channel-free ?l))

  (:action navigate
    :parameters (?r ?y ?z)
    :precondition (and (can-traverse ?r ?y ?z) (at ?r ?y))
    :effect (and (not (at ?r ?y)) (at ?r ?z)))

  (:action sample-soil
    :parameters (?r ?s ?p)
    :precondition (and (at ?r ?p) (at-soil-sample ?p) (equipped-for-soil ?r)
                       (store-of ?s ?r) (empty ?s))
    :effect (and (not (empty ?s)) (full ?s) (have-soil-analysis ?r ?p)
                 (not (at-soil-sample ?p))))

  (:action sample-rock
    :parameters (?r ?s ?p)
    :precondition (and (at ?r ?p) (at-rock-sample ?p) (equipped-for-rock ?r)
                       (store-of ?s ?r) (empty ?s))
    :effect (and (not (empty ?s)) (full ?s) (have-rock-analysis ?r ?p)
                 (not (at-rock-sample ?p))))

  (:action drop
    :parameters (?r ?s)
    :precondition (and (store-of ?s ?r) (full ?s))
    :effect (and (not (full ?s)) (empty ?s)))

  (:action communicate-soil-data
    :parameters (?r ?l ?p ?x ?y)
    :precondition (and (at ?r ?x) (at-lander ?l ?y) (have-soil-analysis ?r ?p)
                       (visible ?x ?y) (channel-free ?l))
    :effect (communicated-soil-data ?p))

  (:action communicate-rock-data
    :parameters (?r ?l ?p ?x ?y)
    :precondition (and (at ?r ?x) (at-lander ?l ?y) (have-rock-analysis ?r ?p)
                       (visible ?x ?y) (channel-free ?l))
    :effect (communicated-rock-data ?p)))
