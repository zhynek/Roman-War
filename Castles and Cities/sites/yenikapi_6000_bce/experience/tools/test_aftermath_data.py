import unittest

from validate_aftermath import load, validate


class AftermathData(unittest.TestCase):
    def test_valid_bounded_recovery_contract(self):
        self.assertEqual(validate(load('governance'), load('balance')), [])

    def test_reject_hidden_skills_and_irrecoverable_injuries(self):
        for case in ['free_xp', 'fast_xp', 'unbounded_xp', 'no_improvement', 'instant_care', 'endless_care', 'reversed_severity', 'invisible_wound', 'nonfinite', 'permanent_death']:
            with self.subTest(case=case):
                data, balance = load('governance'), load('balance')
                tuning = balance['warfare']['aftermath']
                if case == 'free_xp': tuning['experience_per_skill'] = 0
                if case == 'fast_xp': tuning['experience_per_engagement'] = 2
                if case == 'unbounded_xp': tuning['maximum_experience'] = 100
                if case == 'no_improvement': tuning['maximum_experience'] = 3; tuning['experience_per_skill'] = 5
                if case == 'instant_care': tuning['mild_recovery_seasons'] = 0
                if case == 'endless_care': tuning['incapacitated_recovery_seasons'] = 1000000
                if case == 'reversed_severity': tuning['mild_recovery_seasons'] = 3; tuning['incapacitated_recovery_seasons'] = 2
                if case == 'invisible_wound': tuning['mild_injury_hp_loss'] = balance['defense']['hp_per_person']
                if case == 'nonfinite': tuning['mild_injury_hp_loss'] = float('nan')
                if case == 'permanent_death': tuning['death_threshold'] = 0
                self.assertTrue(validate(data, balance), case)

    def test_reject_free_gear_and_unbounded_household_penalties(self):
        for case in ['perfect_beyond_limit', 'instant_repair', 'free_wood', 'free_labor', 'care_zero', 'care_late', 'care_unbounded', 'minor_worse', 'huge_strain', 'new_profile', 'missing_evidence']:
            with self.subTest(case=case):
                data, balance = load('governance'), load('balance')
                tuning = balance['warfare']['aftermath']
                if case == 'perfect_beyond_limit': tuning['equipment_initial_condition'] = 200
                if case == 'instant_repair': tuning['equipment_repair_gain'] = 1000
                if case == 'free_wood': balance['living']['repair_wood'] = 0
                if case == 'free_labor': balance['living']['repair_workers'] = 0
                if case == 'care_zero': tuning['patients_per_worker'] = 0
                if case == 'care_late': tuning['care_priority'] = 5
                if case == 'care_unbounded': tuning['patients_per_worker'] = 100
                if case == 'minor_worse': tuning['household_stress_injury'] = 10; tuning['household_stress_incapacitated'] = 4
                if case == 'huge_strain': tuning['household_stress_incapacitated'] = 1000
                if case == 'new_profile': data['warfare']['aftermath']['profile'] = 'historic_claim'
                if case == 'missing_evidence': del data['warfare']['aftermath']['evidence']
                self.assertTrue(validate(data, balance), case)


if __name__ == '__main__':
    unittest.main()
