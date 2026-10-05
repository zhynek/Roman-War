import copy
import unittest
from validate_assets import load,validate
class AssetData(unittest.TestCase):
    def setUp(self):self.data=[load(n) for n in ['assets','balance','governance','settlement','households']]
    def rejected(self,change):
        changed=copy.deepcopy(self.data);change(changed)
        self.assertTrue(validate(*changed))
    def test_valid(self):self.assertEqual([],validate(*self.data))
    def test_unknown(self):self.rejected(lambda d:d[0]['assets'][0]['objects'].append('fictional_missing'))
    def test_ambiguous(self):self.rejected(lambda d:d[0]['assets'][1]['objects'].append('yk_store_01'))
    def test_office(self):self.rejected(lambda d:d[0]['assets'][0].update(role='watch'))
    def test_project(self):self.rejected(lambda d:d[0]['assets'][0].update(projects=[]))
    def test_principle(self):self.rejected(lambda d:d[0]['principles'][0].update(id='free_food'))
    def test_tutorial(self):self.rejected(lambda d:d[0]['tutorial'][0].update(condition='free_resources'))
    def test_threshold(self):self.rejected(lambda d:d[1]['assets'].update(condition_threshold=99))
    def test_negative(self):self.rejected(lambda d:d[1]['assets'].update(repair_wood=-1))
    def test_inert_stat(self):self.rejected(lambda d:d[1]['assets'].update(prestige=10))
    def test_housing(self):self.rejected(lambda d:d[0].update(housing_steps=['east_home']))
if __name__=='__main__':unittest.main()
