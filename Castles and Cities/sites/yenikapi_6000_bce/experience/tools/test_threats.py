import copy
import unittest

from validate_threats import load, validate


class ThreatData(unittest.TestCase):
    def test_valid_bounded_objectives(self):
        self.assertEqual(validate(load('governance'), load('balance')), [])

    def test_reject_opaque_or_identical_objectives(self):
        for case in ['duplicate', 'reordered', 'same_kind', 'same_place', 'unknown_place', 'same_origin', 'outside', 'nonfinite', 'hidden_stat']:
            with self.subTest(case=case):
                data = load('governance')
                entries = data['warfare']['threats']['encounters']
                if case == 'duplicate': entries[1] = copy.deepcopy(entries[0])
                if case == 'reordered': entries.reverse()
                if case == 'same_kind': entries[1]['kind'] = 'occupy'
                if case == 'same_place': entries[1]['place'] = 'stores'
                if case == 'unknown_place': entries[0]['place'] = 'palace'
                if case == 'same_origin': entries[0]['origins'][1] = copy.deepcopy(entries[0]['origins'][0])
                if case == 'outside': entries[0]['origins'][0] = [60, 60]
                if case == 'nonfinite': entries[0]['origins'][0][0] = float('nan')
                if case == 'hidden_stat': entries[0]['strength_multiplier'] = 5
                self.assertTrue(validate(data, load('balance')), case)

    def test_reject_punishment_loops_and_unbounded_fights(self):
        for case in ['no_quiet', 'short_warning', 'free_contact', 'no_reserve', 'endless', 'instant_probe', 'late_capture', 'excess_loss', 'probe_loot', 'missing_tuning']:
            with self.subTest(case=case):
                data, balance = load('governance'), load('balance')
                tuning = balance['warfare']['threats']
                if case == 'no_quiet': tuning['quiet_seasons'] = 0
                if case == 'short_warning': tuning['warning_seasons'] = 1
                if case == 'free_contact': tuning['contact_warning'] = 4
                if case == 'no_reserve': tuning['recovery_food_seasons'] = 0
                if case == 'endless': tuning['encounters']['stores']['deadline_ticks'] = 1000000
                if case == 'instant_probe': tuning['encounters']['probe']['capture_ticks'] = 50
                if case == 'late_capture': tuning['encounters']['stores']['capture_ticks'] = 1000; tuning['encounters']['stores']['deadline_ticks'] = 500
                if case == 'excess_loss': tuning['encounters']['stores']['supply_loss'] = 100
                if case == 'probe_loot': tuning['encounters']['probe']['supply_loss'] = 1
                if case == 'missing_tuning': del tuning['encounters']['landing']
                self.assertTrue(validate(data, balance), case)


if __name__ == '__main__':
    unittest.main()
