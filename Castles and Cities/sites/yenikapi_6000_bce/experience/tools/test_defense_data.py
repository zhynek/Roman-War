import copy
import unittest
from validate_defense import validate, load

class DefenseData(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate(load('governance'),load('balance')), [])
    def test_negative_and_unbounded_tuning(self):
        for key, value in [('tick_ms',0),('damage',-1),('maximum_defenders',100),('capture_ticks',100000),('step_cm',200),('route_morale',100)]:
            b=load('balance'); b['defense'][key]=value
            self.assertTrue(validate(load('governance'),b), key)
    def test_place_and_profile(self):
        for key,value in [('profile','unknown'),('places',[])]:
            c=load('governance'); c['defense'][key]=value
            self.assertTrue(validate(c,load('balance')))
    def test_closed_content(self):
        c=load('governance');c['defense']['free_weapons']=True
        self.assertTrue(validate(c,load('balance')))

if __name__ == '__main__': unittest.main()
