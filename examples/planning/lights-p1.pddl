;; A negative goal: the broken lamp in the study must end up off.
(define (problem lights-1)
  (:domain lights)
  (:objects study kitchen - room
            desk-lamp reading-lamp strip-light - lamp
            wall-switch - switch)
  (:init (at hall) (door hall study) (door kitchen hall)
         (in wall-switch study) (in desk-lamp study) (in reading-lamp study)
         (in strip-light study)
         (wired wall-switch desk-lamp) (wired wall-switch reading-lamp)
         (on strip-light) (broken strip-light))
  (:goal (and (on desk-lamp) (tidy study) (at kitchen) (not (on strip-light)))))
