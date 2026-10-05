#!/usr/bin/env python3
import unittest
from validate_households import load, validate
class HouseholdData(unittest.TestCase):
    def setUp(self):
        self.c, self.b, self.g, self.s = [load(x) for x in ['households', 'balance', 'governance', 'settlement']]
    def errors(self):
        return validate(self.c, self.b, self.g, self.s)
    def test_valid(self):
        self.assertEqual(self.errors(), [])
    def test_closed_structure(self):
        for key in list(self.c):
            with self.subTest(key=key):
                self.setUp(); self.c[key] = None; self.assertTrue(self.errors())
        self.setUp(); self.c['pretend_history'] = True; self.assertTrue(self.errors())
    def test_stages_and_authority(self):
        self.c['stages'].reverse(); self.assertTrue(self.errors())
        self.setUp(); self.c['orders'][2]['role'] = 'steward'; self.assertTrue(self.errors())
        self.setUp(); self.c['orders'][0]['id'] = 'unknown'; self.assertTrue(self.errors())
    def test_station_links(self):
        mutations = [('building', 'missing'), ('use', 'store'), ('id', 'household_store')]
        for key, value in mutations:
            with self.subTest(key=key):
                self.setUp(); self.c['stations'][0][key] = value; self.assertTrue(self.errors())
        self.setUp(); self.c['orders'][0]['station'] = 'missing'; self.assertTrue(self.errors())
    def test_tuning_guards(self):
        for key, value in [('stage_seasons', 0), ('care_minimum', 0), ('stress_wellbeing_divisor', 0), ('practice_affinity_span', 0), ('learning_food', -1), ('max_stock', 50), ('refuge_stress', 1)]:
            with self.subTest(key=key):
                self.setUp(); self.b['households'][key] = value; self.assertTrue(self.errors())
        self.setUp(); self.b['households']['costs']['refuge'] = -1; self.assertTrue(self.errors())
        self.setUp(); self.b['households']['stages']['recovery']['stress'] = 0; self.assertTrue(self.errors())
    def test_prose_and_interpretation(self):
        self.c['kind'] = 'historical'; self.assertTrue(self.errors())
        self.setUp(); del self.c['presentation']['activity_labels']['refuge_care']; self.assertTrue(self.errors())
        self.setUp(); del self.c['events']['household_started']; self.assertTrue(self.errors())
    def test_optional_separation(self):
        self.assertEqual(self.s['snapshot_id'], 'yenikapi_c6000_bce')
        self.assertNotIn(self.c['id'], self.g['tutorial_projects'])
if __name__ == '__main__':
    unittest.main()
