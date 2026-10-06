#!/usr/bin/env python3
import copy
import unittest
from validate_land import load,validate
class LandData(unittest.TestCase):
    def test_baseline(self):self.assertEqual(validate(*(load(n) for n in ['land','balance','governance','settlement'])),[])
    def test_rejects_invalid_relationships(self):
        mutations=[lambda d:d['sites'].append(copy.deepcopy(d['sites'][0])),lambda d:d['proposals'][0].update(site='missing'),lambda d:d['sites'][0].update(connection='missing'),lambda d:d['sites'][0]['objects'].append('missing'),lambda d:d['projects'][0].update(wood=-1),lambda d:d['projects'][0].update(requires=['missing']),lambda d:d['projects'][0].update(requires=[d['projects'][0]['id']]),lambda d:d['projects'][0]['changes'][0].update(before=['yk_house_01']),lambda d:d['projects'][0]['changes'][1]['after'][0].update(id='yk_house_01'),lambda d:d['households'][0].update(building_id='missing'),lambda d:d['proposals'][2].update(requires_access=False,site='missing'),lambda d:d['sites'][0].update(unknown=1),lambda d:d['alternatives']['north_home'].append('missing')]
        for mutation in mutations:
            d=load('land');mutation(d)
            with self.subTest(mutation=mutations.index(mutation)):self.assertTrue(validate(d,load('balance'),load('governance'),load('settlement')))
    def test_access_precedes_dependent_work(self):
        for key,value in [('access_workers',0),('access_wood',0),('access_priority',6),('minimum_reserve',0)]:
            b=load('balance');b['land'][key]=value
            with self.subTest(key=key):self.assertTrue(validate(load('land'),b,load('governance'),load('settlement')))
if __name__=='__main__':unittest.main()
