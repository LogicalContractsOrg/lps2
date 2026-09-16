# Planning — PDDL problems, solved by LPS2's planner

Classical planning domains and problems in PDDL (blocks, gripper, hanoi,
logistics, elevator, rover, and lights, which uses typing, `or`, quantifiers,
conditional effects and negative and disjunctive goals). LPS2 converts a PDDL file to LPS when it opens it
(src/syntax/lps_pddl.pl) and plans with its own planner; tools/pddl_test.pl
checks every problem's plan.
