"""Negative tests for the reusable district authoring boundary."""
import copy
import json
from pathlib import Path
import unittest
from validate_city import validate_neighborhood
ROOT = Path(__file__).resolve().parents[1]
class NeighborhoodDataTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/'data/neighborhood.json').read_text())
        self.schema = json.loads((ROOT/'schemas/neighborhood.schema.json').read_text())
        self.city = json.loads((ROOT/'data/city.json').read_text())
    def errors(self):
        return validate_neighborhood(self.data,self.schema,self.city)
    def test_valid_data(self):
        original = copy.deepcopy(self.data)
        self.assertEqual(self.errors(), [])
        self.assertEqual(original,self.data)
    def test_reject_unknown_evidence(self):
        self.data['blocks'][0]['evidence_id']='invented'
        self.assertTrue(self.errors())
    def test_reject_inverted_boundary(self):
        self.data['blocks'][0]['polygon_m'].reverse()
        self.assertTrue(self.errors())
    def test_reject_missing_stop(self):
        self.data['stops'][1]['parcel_id']='missing'
        self.assertTrue(self.errors())
    def test_reject_passage_slot(self):
        self.data['blocks'][0]['passages'][0]['index']=999
        self.assertTrue(self.errors())
    def test_reject_disconnected_gateway(self):
        self.data['streets'][0]['points_m'][-1][0]+=1
        self.assertTrue(self.errors())
    def test_reject_later_chronology(self):
        self.data['reference_year_ce']=1261
        self.assertTrue(self.errors())
    def test_reject_duplicate_identity(self):
        self.data['blocks'].append(copy.deepcopy(self.data['blocks'][0]))
        self.assertTrue(self.errors())
if __name__=='__main__':unittest.main()
