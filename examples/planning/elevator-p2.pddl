;; One passenger going down: the `down` action has to be used, which the
;; up-only problems never exercise. Optimal is 4.
(define (problem elevator-down)
  (:domain elevator)
  (:objects p1 f1 f2 f3)
  (:init (above f1 f2) (above f2 f3) (above f1 f3)
         (origin p1 f3) (destin p1 f1)
         (lift-at f1))
  (:goal (served p1)))
