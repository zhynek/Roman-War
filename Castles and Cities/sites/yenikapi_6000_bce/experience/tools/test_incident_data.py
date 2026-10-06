import copy,unittest
from validate_incidents import load,validate
class InvalidIncidentData(unittest.TestCase):
    def test_baseline(self):self.assertEqual(validate(load('incidents'),load('balance')),[])
    def test_bad_references(self):
        for key in ['place','post','asset','prepare','repair']:
            d=load('incidents');d['incidents'][0][key]='missing';self.assertTrue(validate(d,load('balance')),key)
    def test_unfair_timing(self):
        b=load('balance');b['incidents']['warning_seasons']=1;self.assertTrue(validate(load('incidents'),b))
    def test_unknown_content(self):
        d=load('incidents');d['incidents'][0]['reward']=100;self.assertTrue(validate(d,load('balance')))
    def test_free_or_double_materials(self):
        for key in ['wood','work','blanks']:
            d=load('incidents');d['projects'][0][key]=0;self.assertTrue(validate(d,load('balance')))
    def test_duplicate_identity(self):
        d=load('incidents');d['incidents'][1]['id']=d['incidents'][0]['id'];self.assertTrue(validate(d,load('balance')))
if __name__=='__main__':unittest.main()
