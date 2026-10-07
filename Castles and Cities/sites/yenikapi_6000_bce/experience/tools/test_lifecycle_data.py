import copy
import unittest
from validate_lifecycle import load, validate


class LifecycleContent(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate(load('lifecycle'), load('balance')), [])

    def test_invalid(self):
        cases = ['stage', 'duplicate', 'project', 'cycle', 'planned', 'predecessor', 'furniture', 'site', 'cost', 'effect', 'predicate', 'unknown']
        for case in cases:
            with self.subTest(case=case):
                data, balance = load('lifecycle'), load('balance')
                if case == 'stage': data['transitions'][0]['to'] = 'missing'
                if case == 'duplicate': data['projects'].append(copy.deepcopy(data['projects'][0]))
                if case == 'project': data['projects'][0]['requires'].append('missing')
                if case == 'cycle':
                    data['factors']['self_unlock'] = 'Unavailable improvement'
                    data['transitions'][0]['readiness']['all'].append({'id': 'self_unlock', 'kind': 'project', 'project': 'lifecycle_store'})
                if case == 'planned': data['stages'][1]['status'] = 'planned'
                if case == 'predecessor': data['projects'][1]['changes'][0]['expected_revisions']['yk_store_01'] = 1
                if case == 'furniture': data['projects'][1]['changes'][0]['after'][0]['furniture'].pop(0)
                if case == 'site': data['proposals'][-1]['predecessor'] = 'land_cultivate'
                if case == 'cost': balance['lifecycle']['projects']['lifecycle_assembly']['work'] = 0
                if case == 'effect': balance['lifecycle']['projects']['lifecycle_store']['effects']['free_gold'] = 100
                if case == 'predicate': data['transitions'][0]['readiness']['all'][0]['kind'] = 'time_of_day'
                if case == 'unknown': data['secret_bonus'] = 999
                self.assertTrue(validate(data, balance), case)

    def test_every_project_has_exactly_one_proposal(self):
        data, balance = load('lifecycle'), load('balance')
        data['proposals'] = [p for p in data['proposals'] if p['id'] != 'lifecycle_workroom']
        self.assertIn('lifecycle proposal coverage mismatch', validate(data, balance))
        data = load('lifecycle')
        data['proposals'].append(copy.deepcopy(data['proposals'][0]))
        self.assertIn('duplicate proposal', validate(data, balance))

    def test_civic_staffing_references_an_active_project_with_an_asset(self):
        balance = load('balance')
        for id in ['missing_project', 'lifecycle_store']:
            with self.subTest(id=id):
                data = load('lifecycle')
                data['civic_project'] = id
                self.assertIn('civic project must reference an active transition project', validate(data, balance))
        data = load('lifecycle')
        del data['civic_project']
        self.assertTrue(validate(data, balance))
        data = load('lifecycle')
        data['projects'][0]['asset'] = 'unknown_asset'
        self.assertTrue(validate(data, balance))

    @staticmethod
    def forward_profile():
        data = load('lifecycle')
        data['stages'][2]['status'] = 'playable'
        data['transitions'].append({
            'id': 'next_civic_step', 'from': 'village_established', 'to': 'town',
            'project': 'lifecycle_store',
            'readiness': {'all': [{'id': 'population', 'kind': 'population', 'tuning': 'population'}], 'any': []},
        })
        return data

    def test_civic_edges_are_forward_and_in_replay_order(self):
        balance = load('balance')
        self.assertEqual(validate(self.forward_profile(), balance), [])
        for destination in ['village_foundation', 'village_established']:
            with self.subTest(destination=destination):
                data = self.forward_profile()
                data['transitions'][-1]['to'] = destination
                self.assertIn('civic transition must advance stage', validate(data, balance))
        data = self.forward_profile()
        data['transitions'].reverse()
        self.assertIn('transitions must follow stage order', validate(data, balance))

    def test_authored_revisions_match_runtime_successors(self):
        data, balance = load('lifecycle'), load('balance')
        data['projects'][1]['changes'][0]['after'][0]['revision'] = 99
        self.assertIn('invalid successor revision', validate(data, balance))
        data = load('lifecycle')
        data['projects'][0]['changes'][0]['after'][0]['revision'] = 2
        self.assertIn('addition must start at revision 1', validate(data, balance))

    def test_later_project_can_alter_a_newly_revised_building(self):
        data, balance = load('lifecycle'), load('balance')
        # A synthetic second alteration adds a working area to the same store.
        # It keeps the bounded schema's existing project/tuning identities while
        # exercising the next physical revision and matching site succession.
        first, later = data['projects'][1:]
        later['changes'] = copy.deepcopy(first['changes'])
        later['changes'][0]['expected_revisions']['yk_store_01'] = 3
        later['changes'][0]['after'][0]['revision'] = 4
        later['requires'].append(first['id'])
        later['asset'] = first['asset']
        later['at'] = first['at']
        later['benefit_target']['predecessor'] = first['id']
        proposal = data['proposals'][-1]
        proposal['predecessor'] = first['id']
        proposal['site'] = data['proposals'][1]['site']
        proposal['asset'] = first['asset']
        self.assertEqual(validate(data, balance), [])
        later['changes'][0]['expected_revisions']['yk_store_01'] = 2
        later['changes'][0]['after'][0]['revision'] = 3
        self.assertIn('stale authored predecessor', validate(data, balance))

    def test_incremental_effect_must_reach_declared_total(self):
        data, balance = load('lifecycle'), load('balance')
        balance['lifecycle']['projects']['lifecycle_store']['effects']['storage'] = 600
        self.assertIn('cumulative benefit target mismatch', validate(data, balance))
        data['projects'][1]['benefit_target']['total'] = 720
        self.assertEqual(validate(data, balance), [])

    def test_replacement_site_capacity_must_reach_declared_total(self):
        data, balance = load('lifecycle'), load('balance')
        data['proposals'][-1]['work'] = 9
        self.assertIn('cumulative benefit target mismatch', validate(data, balance))
        data['projects'][-1]['benefit_target']['total'] = 9
        self.assertEqual(validate(data, balance), [])
        data['projects'][-1]['benefit_target']['predecessor'] = 'land_cultivate'
        self.assertIn('benefit target must follow the same site predecessor', validate(data, balance))

    def test_improvements_have_closed_targets_and_derived_copy(self):
        data, balance = load('lifecycle'), load('balance')
        del data['projects'][1]['benefit_target']
        self.assertIn('improvement lacks benefit target', validate(data, balance))
        data = load('lifecycle')
        data['projects'][1]['presentation']['benefit'] = 'Add 60 places; total improvement is 180.'
        self.assertIn('benefit copy must render derived values', validate(data, balance))
        data = load('lifecycle')
        data['projects'][1]['benefit_target']['key'] = 'unread_effect'
        self.assertTrue(validate(data, balance))


if __name__ == '__main__': unittest.main()
