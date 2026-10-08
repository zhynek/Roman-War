import copy
import unittest

from validate_fortifications import load, validate


class FortificationData(unittest.TestCase):
    def test_valid_paid_screens_and_plans(self):
        self.assertEqual(validate(load('governance'), load('balance')), [])

    def test_reject_economic_and_adoption_shortcuts(self):
        for case in ['free', 'instant', 'passive', 'missing_shelter', 'wrong_office', 'extra_cost', 'unknown_tuning']:
            with self.subTest(case=case):
                data, balance = load('governance'), load('balance')
                project = data['warfare']['fortifications']['projects'][0]
                price = balance['warfare']['fortifications']['projects']['warfare_store_screen']
                if case == 'free': price['wood'] = 0
                if case == 'instant': price['work'] = 0
                if case == 'passive': price['effects'] = {'security': 20}
                if case == 'missing_shelter': project['requires'] = []
                if case == 'wrong_office': project['role'] = 'steward'
                if case == 'extra_cost': project['wood'] = 12
                if case == 'unknown_tuning': project['tuning'] = 'missing'
                self.assertTrue(validate(data, balance), case)

    def test_reject_closed_or_misplaced_entrances(self):
        for case in ['closed_gap', 'doorway', 'degenerate', 'reused_identity', 'unknown_source', 'false_kind']:
            with self.subTest(case=case):
                data = load('governance')
                project = data['warfare']['fortifications']['projects'][0]
                record = project['changes'][0]['after'][0]
                if case == 'closed_gap': record['points'][1] = [6, 34]
                if case == 'doorway': record['points'] = [[-8, 20], [-3, 20]]
                if case == 'degenerate': record['points'][1] = copy.deepcopy(record['points'][0])
                if case == 'reused_identity': record['id'] = 'yk_screen_01'
                if case == 'unknown_source': record['source_ids'] = ['invented_source']
                if case == 'false_kind': record['kind'] = 'building'
                self.assertTrue(validate(data, load('balance')), case)

    def test_reject_bad_plan_or_protection_references(self):
        for case in ['unknown_place', 'duplicate_position', 'unknown_slot', 'wrong_stand', 'duplicate_defense', 'excess_radius', 'excess_protection', 'nonfinite']:
            with self.subTest(case=case):
                data, balance = load('governance'), load('balance')
                fort = data['warfare']['fortifications']
                tuning = balance['warfare']['fortifications']
                if case == 'unknown_place': fort['slots']['assembly'] = 'missing'
                if case == 'duplicate_position': fort['positions'][1] = copy.deepcopy(fort['positions'][0])
                if case == 'unknown_slot': fort['slots']['free_soldiers'] = 'watch_assembly'
                if case == 'wrong_stand': fort['defenses'][0]['position'] = 'north'
                if case == 'duplicate_defense': fort['defenses'][1] = copy.deepcopy(fort['defenses'][0])
                if case == 'excess_radius': tuning['radius_cm'] = 2000
                if case == 'excess_protection': tuning['protection'] = 30
                if case == 'nonfinite': fort['positions'][0]['at'][0] = float('nan')
                self.assertTrue(validate(data, balance), case)


if __name__ == '__main__':
    unittest.main()
