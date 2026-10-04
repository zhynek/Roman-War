import copy
import json
import unittest
from validate_settlement import ROOT,validate
class DataTests(unittest.TestCase):
    def setUp(self):self.data=json.loads((ROOT/'data/settlement.json').read_text())
    def bad(self):self.assertTrue(validate(self.data))
    def test_valid(self):self.assertEqual([],validate(self.data))
    def test_nonfinite(self):self.data['objects'][0]['at'][0]=float('nan');self.bad()
    def test_duplicate_identity(self):self.data['objects'].append(copy.deepcopy(self.data['objects'][0]));self.bad()
    def test_later_roof(self):self.data['objects'][0]['roof']='tile';self.bad()
    def test_unknown_source(self):self.data['objects'][0]['source_ids']=['unknown'];self.bad()
    def test_invented_history(self):self.data['objects'][0]['evidence']='documented';self.bad()
    def test_wrong_epoch(self):self.data['nominal_year_bce']=1200;self.bad()
    def test_implicit_growth(self):self.data['population']=50;self.bad()
    def test_furniture_bounds(self):self.data['objects'][0]['furniture'][0]['at']=[19,19];self.bad()
    def test_missing_door_record(self):del self.data['objects'][0]['size'];self.bad()
    def test_bad_lineage(self):self.data['objects'][0]['change']['predecessors']=['medieval_house'];self.bad()
    def test_duplicate_furniture(self):self.data['objects'][0]['furniture'].append(copy.deepcopy(self.data['objects'][0]['furniture'][0]));self.bad()
    def test_degenerate_path(self):self.data['objects'][9]['points'][1]=self.data['objects'][9]['points'][0];self.bad()
    def test_duplicate_stop(self):self.data['stops'][1]['key']='1';self.bad()
if __name__=='__main__':unittest.main()
