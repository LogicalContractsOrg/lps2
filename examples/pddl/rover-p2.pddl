;; Both samples, so the store has to be dropped in between. This is the
;; problem the `drop` action exists for.
(define (problem rover-2)
  (:domain rover)
  (:objects rover1 store1 lander1 wp0 wp1 wp2)
  (:init (at rover1 wp0) (at-lander lander1 wp0) (channel-free lander1)
         (store-of store1 rover1) (empty store1)
         (equipped-for-soil rover1) (equipped-for-rock rover1)
         (can-traverse rover1 wp0 wp1) (can-traverse rover1 wp1 wp0)
         (can-traverse rover1 wp1 wp2) (can-traverse rover1 wp2 wp1)
         (at-soil-sample wp1) (at-rock-sample wp2)
         (visible wp0 wp0) (visible wp1 wp0) (visible wp2 wp0))
  (:goal (and (communicated-soil-data wp1) (communicated-rock-data wp2))))
